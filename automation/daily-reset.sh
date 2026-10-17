#!/usr/bin/env bash
# Guarded disposable-test world reset. Wipes the world directories of a
# disposable server under the shared lifecycle lock, after a verified pre-wipe
# backup, and reopens the MCSManager-managed instance afterward.
#
# Never run this against a live season world. It self-expires on RESET_UNTIL so
# the test phase cannot "forget" to stop.
#
# Environment (see .env.example):
#   SERVER_DIR, CONTAINER, DATA_DEST, STATE_DIR, RESET_UNTIL, BACKUP_TIMEZONE,
#   SEEDS_FILE, MCSM_WEB_CONTAINER, MCSM_CONFIG, MCSM_NODE_ID,
#   MCSM_INSTANCE_UUID, BLUEMAP_MAPS, PREWIPE_BACKUP, timeouts.
set -euo pipefail
umask 077

RESET_UNTIL="${RESET_UNTIL:-2030-01-01}" # last reset day is the day before this date
CONTAINER="${CONTAINER:-minecraft}"
SERVER_DIR="${SERVER_DIR:-}"
STATE_DIR="${STATE_DIR:-/srv/minecraft/.reset-state}"
DATA_DEST="${DATA_DEST:-/data}"
BACKUP_TIMEZONE="${BACKUP_TIMEZONE:-UTC}"
SEEDS_FILE="${SEEDS_FILE:-$(dirname -- "$0")/seeds.txt}"
READINESS_TIMEOUT="${READINESS_TIMEOUT:-150}"
READINESS_INTERVAL="${READINESS_INTERVAL:-5}"
RCON_CALL_TIMEOUT="${RCON_CALL_TIMEOUT:-10}"
RCON_KILL_AFTER="${RCON_KILL_AFTER:-2}"
SHUTDOWN_TIMEOUT="${SHUTDOWN_TIMEOUT:-150}"
BLUEMAP_PURGE_TIMEOUT="${BLUEMAP_PURGE_TIMEOUT:-120}"
BLUEMAP_MAPS="${BLUEMAP_MAPS:-world,world_the_nether,world_the_end}"
BLUEMAP_SPAWN_VIEW_TIMEOUT="${BLUEMAP_SPAWN_VIEW_TIMEOUT:-60}"
PREWIPE_BACKUP="${PREWIPE_BACKUP:-1}"
MCSM_WEB_CONTAINER="${MCSM_WEB_CONTAINER:-mcsm-web}"
MCSM_CONFIG="${MCSM_CONFIG:-/opt/mcsmanager/web/data/RemoteServiceConfig}"
MCSM_NODE_ID="${MCSM_NODE_ID:-}"
MCSM_INSTANCE_UUID="${MCSM_INSTANCE_UUID:-}"

log() { printf '%s %s\n' "$(TZ="$BACKUP_TIMEZONE" date '+%Y-%m-%d %H:%M:%S %Z')" "$*"; }
die() { printf 'daily-reset: %s\n' "$*" >&2; exit 2; }

# Expiry is deliberately the first operational check: expired jobs do not touch
# the state directory, server files, or Docker.
today="$(TZ="$BACKUP_TIMEZONE" date +%F)"
[[ "$RESET_UNTIL" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]] || die 'RESET_UNTIL must be YYYY-MM-DD'
if [[ ! "$today" < "$RESET_UNTIL" ]]; then
  log "reset window expired (active until < $RESET_UNTIL) — no-op"
  exit 0
fi

[[ -n "$SERVER_DIR" ]] || die 'SERVER_DIR must be set to the instance data directory'
[[ "$SERVER_DIR" != / ]] || die 'SERVER_DIR cannot be /'
[[ ! -L "$SERVER_DIR" ]] || die 'SERVER_DIR must not be a symlink'
[[ -d "$SERVER_DIR" ]] || die 'SERVER_DIR must be an existing directory'
server_dir="$(realpath -e -- "$SERVER_DIR")"
case "$server_dir" in /|/home|/root|/srv|/mnt|/opt|/usr|/var|/etc) die 'SERVER_DIR resolves to a protected parent directory' ;; esac
[[ -f "$server_dir/server.properties" && ! -L "$server_dir/server.properties" ]] || die 'SERVER_DIR must contain a regular, non-symlink server.properties'
[[ "$server_dir" != *$'\n'* ]] || die 'SERVER_DIR may not contain a newline'

[[ ! -L "$server_dir/plugins" ]] || die 'plugins directory must not be a symlink'
if [[ -e "$server_dir/plugins" ]]; then
  [[ -d "$server_dir/plugins" && "$(realpath -e -- "$server_dir/plugins")" == "$server_dir/plugins" ]] || die 'plugins directory must resolve inside SERVER_DIR'
fi
for w in world world_nether world_the_end; do
  [[ ! -L "$server_dir/$w" ]] || die "$w must not be a symlink"
  if [[ -e "$server_dir/$w" ]]; then
    [[ -d "$server_dir/$w" ]] || die "$w exists but is not a directory"
    [[ "$(realpath -e -- "$server_dir/$w")" == "$server_dir/$w" ]] || die "$w resolves outside SERVER_DIR"
  fi
done

# Validate BlueMap configuration before backup/shutdown/wipe. Its map IDs are
# passed as one RCON argument each and must remain plain bounded identifiers.
bluemap_dir="$server_dir/plugins/BlueMap"
bluemap_installed=false
bluemap_maps=()
[[ ! -L "$bluemap_dir" ]] || die 'BlueMap directory must not be a symlink'
if [[ -e "$bluemap_dir" ]]; then
  [[ -d "$bluemap_dir" && "$(realpath -e -- "$bluemap_dir")" == "$bluemap_dir" ]] || die 'BlueMap directory must be a real directory inside SERVER_DIR'
  bluemap_installed=true
  IFS=, read -r -a bluemap_maps <<< "$BLUEMAP_MAPS"
  ((${#bluemap_maps[@]} > 0)) || die 'BLUEMAP_MAPS must contain at least one map ID'
  for map_id in "${bluemap_maps[@]}"; do
    [[ "$map_id" =~ ^[A-Za-z0-9_-]+$ ]] || die 'BLUEMAP_MAPS must be comma-separated simple map IDs'
  done
fi

compass_dir="$server_dir/plugins/AwepeepsBlueMapCompass"
compass_marker_file="$compass_dir/banner-markers.yml"
[[ ! -L "$compass_dir" ]] || die 'BlueMap Compass data directory must not be a symlink'
if [[ -e "$compass_dir" ]]; then
  [[ -d "$compass_dir" && "$(realpath -e -- "$compass_dir")" == "$compass_dir" ]] || die 'BlueMap Compass data directory must be a real directory inside SERVER_DIR'
fi
reset_compass_markers=false
[[ ! -L "$compass_marker_file" ]] || die 'BlueMap Compass banner marker data must not be a symlink'
if [[ -e "$compass_marker_file" ]]; then
  [[ -f "$compass_marker_file" && "$(stat -c %h -- "$compass_marker_file")" == 1 && "$(realpath -e -- "$compass_marker_file")" == "$compass_marker_file" ]] \
    || die 'BlueMap Compass banner marker data must be a single-link regular file inside its plugin directory'
  reset_compass_markers=true
fi

test_kit_dir="$server_dir/plugins/AwepeepsSpawnKit"
test_kit_state_file="$test_kit_dir/issued-kits.yml"
reset_test_kit_state=false
[[ ! -L "$test_kit_dir" ]] || die 'Awepeeps Spawn Kit data directory must not be a symlink'
if [[ -e "$test_kit_dir" ]]; then
  [[ -d "$test_kit_dir" && "$(realpath -e -- "$test_kit_dir")" == "$test_kit_dir" ]] \
    || die 'Awepeeps Spawn Kit data directory must be a real directory inside SERVER_DIR'
fi
[[ ! -L "$test_kit_state_file" ]] || die 'Awepeeps Spawn Kit issuance data must not be a symlink'
if [[ -e "$test_kit_state_file" ]]; then
  [[ -f "$test_kit_state_file" && "$(stat -c %h -- "$test_kit_state_file")" == 1 && "$(realpath -e -- "$test_kit_state_file")" == "$test_kit_state_file" ]] \
    || die 'Awepeeps Spawn Kit issuance data must be a single-link regular file inside its plugin directory'
  reset_test_kit_state=true
fi

[[ -n "$CONTAINER" && "$CONTAINER" != -* ]] || die 'CONTAINER must be a non-empty container name'
[[ "$DATA_DEST" == /* && "$DATA_DEST" != / ]] || die 'DATA_DEST must be an absolute container path such as /data'
{ [[ "$READINESS_TIMEOUT" =~ ^[0-9]+$ ]] && (( READINESS_TIMEOUT > 0 )); } || die 'READINESS_TIMEOUT must be a positive integer'
{ [[ "$READINESS_INTERVAL" =~ ^[0-9]+$ ]] && (( READINESS_INTERVAL > 0 )); } || die 'READINESS_INTERVAL must be a positive integer'
{ [[ "$RCON_CALL_TIMEOUT" =~ ^[0-9]+$ ]] && (( RCON_CALL_TIMEOUT > 0 )); } || die 'RCON_CALL_TIMEOUT must be a positive integer'
[[ "$RCON_KILL_AFTER" =~ ^[0-9]+$ ]] || die 'RCON_KILL_AFTER must be a non-negative integer'
{ [[ "$SHUTDOWN_TIMEOUT" =~ ^[0-9]+$ ]] && (( SHUTDOWN_TIMEOUT > 0 )); } || die 'SHUTDOWN_TIMEOUT must be a positive integer'
{ [[ "$BLUEMAP_PURGE_TIMEOUT" =~ ^[0-9]+$ ]] && (( BLUEMAP_PURGE_TIMEOUT > 0 )); } || die 'BLUEMAP_PURGE_TIMEOUT must be a positive integer'
{ [[ "$BLUEMAP_SPAWN_VIEW_TIMEOUT" =~ ^[0-9]+$ ]] && (( BLUEMAP_SPAWN_VIEW_TIMEOUT > 0 )); } || die 'BLUEMAP_SPAWN_VIEW_TIMEOUT must be a positive integer'
[[ "$MCSM_NODE_ID" =~ ^[A-Fa-f0-9]{1,64}$ ]] || die 'MCSM_NODE_ID must be set to the panel node id'
[[ "$MCSM_INSTANCE_UUID" =~ ^[a-f0-9]{32}$ ]] || die 'MCSM_INSTANCE_UUID must be a 32-character hex instance id'
[[ "$MCSM_WEB_CONTAINER" =~ ^[A-Za-z0-9_.-]+$ ]] || die 'MCSM_WEB_CONTAINER is invalid'
command -v timeout >/dev/null 2>&1 || die 'GNU timeout is required to bound RCON calls'
[[ -r "$(dirname -- "$0")/mcsm-start.js" ]] || die 'mcsm-start.js must be installed beside this script'
[[ -f "$(dirname -- "$0")/whitelist-check.sh" && ! -L "$(dirname -- "$0")/whitelist-check.sh" ]] \
  || die 'whitelist-check.sh must be installed beside this script'
[[ ! -L "$STATE_DIR" ]] || die 'STATE_DIR must not be a symlink'
mkdir -p -- "$STATE_DIR"
[[ ! -L "$STATE_DIR/lifecycle.lock" ]] || die 'lock file must not be a symlink'
lockfile="$STATE_DIR/lifecycle.lock"
[[ ! -e "$lockfile" || ( -f "$lockfile" && ! -L "$lockfile" && "$(stat -c %h -- "$lockfile")" == 1 ) ]] || die 'lock file must be a single-link regular file'
exec 9>>"$lockfile"
[[ -f "$lockfile" && ! -L "$lockfile" && "$(stat -c %h -- "$lockfile")" == 1 ]] || die 'lock file changed or is hard-linked'
flock -n 9 || die 'another daily reset is already running'

# A successful private snapshot is a hard precondition for every destructive
# reset. The backup inherits the lifecycle lock rather than reacquiring it.
if [[ "$PREWIPE_BACKUP" == 1 ]]; then
  backup_script="$(dirname -- "$0")/backup.sh"
  [[ -f "$backup_script" && ! -L "$backup_script" ]] || die 'backup.sh missing; refusing wipe'
  BACKUP_LOCK_HELD=1 SERVER_DIR="$server_dir" STATE_DIR="$STATE_DIR" CONTAINER="$CONTAINER" \
    bash "$backup_script" || die 'pre-wipe backup failed; refusing wipe'
elif [[ "$PREWIPE_BACKUP" != 0 ]]; then
  die 'PREWIPE_BACKUP must be 0 or 1'
fi

# Confirm this exact host directory is mounted into the requested container data
# path. This prevents a typo from pairing a valid container with another folder.
mounts="$(docker inspect --format '{{range .Mounts}}{{println .Type .Source .Destination}}{{end}}' "$CONTAINER")" || die 'could not inspect Docker container'
expected_mount="bind $server_dir $DATA_DEST"
grep -Fqx -- "$expected_mount" <<<"$mounts" || die "container $CONTAINER does not bind-mount $server_dir at $DATA_DEST"
running="$(docker inspect --format '{{.State.Running}}' "$CONTAINER")" || die 'could not read Docker container state'
[[ "$running" == true ]] || die "container $CONTAINER is not running; refusing reset"

# Parse seed lines literally. Do not use them as sed expressions or shell code.
seeds=()
if [[ -s "$SEEDS_FILE" ]]; then
  while IFS= read -r line || [[ -n "$line" ]]; do
    [[ "$line" =~ ^[[:space:]]*(#|$) ]] && continue
    [[ "$line" =~ ^-?[0-9]+$ ]] || die "invalid seed (expected a literal integer): $line"
    seeds+=("$line")
  done < "$SEEDS_FILE"
fi
idx_file="$STATE_DIR/seed-index"
index=0
[[ ! -L "$idx_file" ]] || die 'seed-index must not be a symlink'
if [[ -f "$idx_file" ]]; then
  IFS= read -r index < "$idx_file" || true
  [[ "$index" =~ ^[0-9]+$ ]] || die 'seed-index must contain a non-negative integer'
fi
[[ ${#index} -le 18 ]] || die 'seed-index is too large'
index=$((10#$index))
if (( ${#seeds[@]} > 0 )); then
  seed="${seeds[$(( index % ${#seeds[@]} ))]}"
else
  seed=''
fi

awk 'BEGIN { seed_count=0; name_count=0 } /^level-seed=/ { seed_count++ } /^level-name=/ { name_count++; if ($0 != "level-name=world") name_ok=0; else name_ok=1 } END { exit (seed_count == 1 && name_count == 1 && name_ok ? 0 : 1) }' \
  "$server_dir/server.properties" || die 'server.properties must contain exactly one level-seed key and exactly level-name=world'

log "requesting graceful RCON shutdown for $CONTAINER"
# MCSManager's Docker handler removes the exited container. Start wait first so
# its exit code remains observable even after that removal.
wait_file="$(mktemp "$STATE_DIR/docker-wait.XXXXXX")"
docker wait "$CONTAINER" >"$wait_file" 2>/dev/null &
wait_pid=$!
cleanup_wait() { kill "$wait_pid" 2>/dev/null || true; rm -f -- "$wait_file"; }
trap cleanup_wait EXIT
timeout --signal=TERM --kill-after="${RCON_KILL_AFTER}s" "${RCON_CALL_TIMEOUT}s" docker exec "$CONTAINER" rcon-cli 'save-all flush' >/dev/null 2>&1 || die 'RCON save-all flush failed; no files were changed'
timeout --signal=TERM --kill-after="${RCON_KILL_AFTER}s" "${RCON_CALL_TIMEOUT}s" docker exec "$CONTAINER" rcon-cli 'stop' >/dev/null 2>&1 || die 'RCON stop failed; no files were changed'
shutdown_start=$SECONDS
while kill -0 "$wait_pid" 2>/dev/null && (( SECONDS - shutdown_start < SHUTDOWN_TIMEOUT )); do sleep 1; done
if kill -0 "$wait_pid" 2>/dev/null; then
  die "container did not exit within ${SHUTDOWN_TIMEOUT}s; no files were changed"
fi
wait "$wait_pid" 2>/dev/null || die 'docker wait failed; no files were changed'
exit_code="$(cat "$wait_file")"
[[ "$exit_code" == 0 ]] || die "container exited with status ${exit_code:-unknown}; no files were changed"
rm -f -- "$wait_file"
trap - EXIT

# Rewrite only the level-seed property using awk variables, preserving all other
# content and avoiding interpretation of seed characters by sed.
props_tmp="$(mktemp "$server_dir/.server.properties.XXXXXX")"
trap 'rm -f -- "${props_tmp:-}"' EXIT
awk -v value="$seed" 'BEGIN { count=0 } /^level-seed=/ { count++; if (count == 1) print "level-seed=" value; next } { print } END { if (count != 1) exit 42 }' \
  "$server_dir/server.properties" > "$props_tmp" || die 'server.properties must contain exactly the expected level-seed key'
chmod --reference="$server_dir/server.properties" "$props_tmp"
mv -f -- "$props_tmp" "$server_dir/server.properties"
props_tmp=''

# Revalidate managed state files after stop and before touching worlds. Their
# removal is deferred until every world directory has been deleted successfully.
if [[ "$reset_compass_markers" == true ]]; then
  [[ ! -L "$compass_dir" && -d "$compass_dir" && "$(realpath -e -- "$compass_dir")" == "$compass_dir" ]] \
    || die 'BlueMap Compass data directory changed; refusing banner-marker reset'
  [[ ! -L "$compass_marker_file" ]] || die 'BlueMap Compass banner marker data became a symlink'
  [[ -f "$compass_marker_file" && "$(stat -c %h -- "$compass_marker_file")" == 1 && "$(realpath -e -- "$compass_marker_file")" == "$compass_marker_file" ]] \
    || die 'BlueMap Compass banner marker data changed; refusing reset'
fi
if [[ "$reset_test_kit_state" == true ]]; then
  [[ ! -L "$test_kit_dir" && -d "$test_kit_dir" && "$(realpath -e -- "$test_kit_dir")" == "$test_kit_dir" ]] \
    || die 'Awepeeps Spawn Kit data directory changed; refusing issuance reset'
  [[ ! -L "$test_kit_state_file" ]] || die 'Awepeeps Spawn Kit issuance data became a symlink'
  [[ -f "$test_kit_state_file" && "$(stat -c %h -- "$test_kit_state_file")" == 1 && "$(realpath -e -- "$test_kit_state_file")" == "$test_kit_state_file" ]] \
    || die 'Awepeeps Spawn Kit issuance data changed; refusing reset'
fi

for w in world world_nether world_the_end; do
  [[ ! -L "$server_dir/$w" ]] || die "$w became a symlink; refusing deletion"
  if [[ -e "$server_dir/$w" ]]; then
    [[ "$(realpath -e -- "$server_dir/$w")" == "$server_dir/$w" ]] || die "$w resolves outside SERVER_DIR; refusing deletion"
    rm -rf -- "${server_dir:?}/$w"
  fi
done

# Clear the one-time issuance tombstone only after every world was removed.
# The mandatory pre-wipe backup preserves it for recovery.
if [[ "$reset_test_kit_state" == true ]]; then
  [[ ! -L "$test_kit_dir" && -d "$test_kit_dir" && "$(realpath -e -- "$test_kit_dir")" == "$test_kit_dir" ]] \
    || die 'Awepeeps Spawn Kit data directory changed; refusing issuance reset'
  [[ ! -L "$test_kit_state_file" ]] || die 'Awepeeps Spawn Kit issuance data became a symlink'
  if [[ -e "$test_kit_state_file" ]]; then
    [[ -f "$test_kit_state_file" && "$(stat -c %h -- "$test_kit_state_file")" == 1 && "$(realpath -e -- "$test_kit_state_file")" == "$test_kit_state_file" ]] \
      || die 'Awepeeps Spawn Kit issuance data changed; refusing reset'
    rm -- "$test_kit_state_file"
    log 'Awepeeps Spawn Kit issuance state reset for the fresh world'
  fi
fi

# Banner markers point into the disposable world, so clear only their persisted
# index after the worlds have all been deleted. The pre-wipe archive preserves it.
if [[ "$reset_compass_markers" == true ]]; then
  [[ ! -L "$compass_dir" && -d "$compass_dir" && "$(realpath -e -- "$compass_dir")" == "$compass_dir" ]] \
    || die 'BlueMap Compass data directory changed; refusing banner-marker reset'
  [[ ! -L "$compass_marker_file" ]] || die 'BlueMap Compass banner marker data became a symlink'
  if [[ -e "$compass_marker_file" ]]; then
    [[ -f "$compass_marker_file" && "$(stat -c %h -- "$compass_marker_file")" == 1 && "$(realpath -e -- "$compass_marker_file")" == "$compass_marker_file" ]] \
      || die 'BlueMap Compass banner marker data changed; refusing reset'
    rm -- "$compass_marker_file"
    log 'BlueMap Compass banner markers reset for the fresh world'
  fi
fi

log "worlds wiped; asking MCSManager to recreate $CONTAINER from its saved configuration"
docker exec -i "$MCSM_WEB_CONTAINER" node - "$MCSM_CONFIG/$MCSM_NODE_ID.json" "$MCSM_INSTANCE_UUID" < "$(dirname -- "$0")/mcsm-start.js" || die 'MCSManager did not confirm instance/open; seed index was not advanced'
# Poll RCON until the server accepts commands, then set and verify the fresh
# world's gamerule in every dimension before committing seed rotation.
log "waiting up to ${READINESS_TIMEOUT}s for Minecraft readiness"
ready=false
readiness_start=$SECONDS
while (( SECONDS - readiness_start < READINESS_TIMEOUT )); do
  remaining=$(( READINESS_TIMEOUT - (SECONDS - readiness_start) ))
  call_timeout=$RCON_CALL_TIMEOUT
  (( call_timeout > remaining )) && call_timeout=$remaining
  if timeout --signal=TERM --kill-after="${RCON_KILL_AFTER}s" "${call_timeout}s" docker exec "$CONTAINER" rcon-cli 'minecraft:list' >/dev/null 2>&1; then
    ready=true
    break
  fi
  remaining=$(( READINESS_TIMEOUT - (SECONDS - readiness_start) ))
  (( remaining > 0 )) || break
  sleep_for=$READINESS_INTERVAL
  (( sleep_for > remaining )) && sleep_for=$remaining
  sleep "$sleep_for"
done
[[ "$ready" == true ]] || die "Minecraft did not become RCON-ready within ${READINESS_TIMEOUT}s; seed index was not advanced"
for dimension in minecraft:overworld minecraft:the_nether minecraft:the_end; do
  timeout --signal=TERM --kill-after="${RCON_KILL_AFTER}s" "${RCON_CALL_TIMEOUT}s" docker exec "$CONTAINER" rcon-cli "execute in $dimension run gamerule minecraft:players_sleeping_percentage 50" >/dev/null \
    || die "could not set sleeping percentage in $dimension; seed index was not advanced"
  result="$(timeout --signal=TERM --kill-after="${RCON_KILL_AFTER}s" "${RCON_CALL_TIMEOUT}s" docker exec "$CONTAINER" rcon-cli "execute in $dimension run gamerule minecraft:players_sleeping_percentage" 2>/dev/null)" \
    || die "could not verify sleeping percentage in $dimension; seed index was not advanced"
  [[ "$result" =~ (^|[^0-9])50([^0-9]|$) ]] \
    || die "sleeping percentage in $dimension did not verify as 50; seed index was not advanced"
done

# The whitelist must survive a fresh world and a container recreate. The image
# can rewrite server.properties from its environment at startup, so verify the
# running server still enforces it before anything else is committed.
log 'verifying whitelist enforcement on the running server'
SERVER_DIR="$server_dir" bash "$(dirname -- "$0")/whitelist-check.sh" \
  || die 'whitelist is not enforced on the running server; seed index was not advanced'

# AwepeepsSpawnKit 1.2.x and later load the chunks they need asynchronously with
# plugin chunk tickets and release them when the build finishes, so the reset must
# not force-load a spawn area itself: a temporary forceload could linger, and the
# old bound (sized for the removed 32-block site search) no longer describes the
# layout. The plugin rebuilds the protected core and the house at the fresh world
# spawn on its own once the issuance record is cleared above.

# Purging is an enqueue gate: BlueMap may take much longer to render the new
# worlds, but every configured map must acknowledge a purge before seed commit.
if [[ "$bluemap_installed" == true ]]; then
  for map_id in "${bluemap_maps[@]}"; do
    purge_start=$SECONDS
    while :; do
      remaining=$(( BLUEMAP_PURGE_TIMEOUT - (SECONDS - purge_start) ))
      (( remaining > 0 )) || die "BlueMap did not acknowledge purge for map $map_id within ${BLUEMAP_PURGE_TIMEOUT}s; seed index was not advanced"
      call_timeout=$RCON_CALL_TIMEOUT
      (( call_timeout > remaining )) && call_timeout=$remaining
      purge_result="$(timeout --signal=TERM --kill-after="${RCON_KILL_AFTER}s" "${call_timeout}s" docker exec "$CONTAINER" rcon-cli "bluemap purge $map_id" 2>/dev/null)" \
        || die "BlueMap purge command failed for map $map_id; seed index was not advanced"
      # RCON may include ANSI terminal colors and Minecraft's section color codes.
      clean_result="$(printf '%s' "$purge_result" | tr -d '\r' | sed -E $'s/\\x1B\\[[0-9;]*[[:alpha:]]//g; s/§[0-9A-FK-ORa-fk-orxX]//g')"
      if grep -Fxq "Scheduled a new task to purge map $map_id" <<< "$clean_result"; then
        log "BlueMap accepted purge for map $map_id (rendering continues asynchronously)"
        break
      fi
      if [[ "${clean_result,,}" == *loading* ]]; then
        remaining=$(( BLUEMAP_PURGE_TIMEOUT - (SECONDS - purge_start) ))
        (( remaining > 0 )) || die "BlueMap was still loading after ${BLUEMAP_PURGE_TIMEOUT}s; seed index was not advanced"
        sleep_for=$READINESS_INTERVAL
        (( sleep_for > remaining )) && sleep_for=$remaining
        sleep "$sleep_for"
        continue
      fi
      die "BlueMap did not confirm purge for map $map_id; seed index was not advanced"
    done
  done
  # The map view is cosmetic: re-point each map at the fresh world spawn and
  # enforce the inhabited-time policy, then reload BlueMap so the settings take
  # effect without a restart. This runs after every configured map acknowledged
  # its purge (so BlueMap is loaded). Any failure warns only and must never block
  # seed rotation.
  if [[ -f "$(dirname -- "$0")/bluemap-spawn-view.py" && ! -L "$(dirname -- "$0")/bluemap-spawn-view.py" ]] \
     && timeout --signal=TERM --kill-after="${RCON_KILL_AFTER}s" "${BLUEMAP_SPAWN_VIEW_TIMEOUT}s" \
          python3 "$(dirname -- "$0")/bluemap-spawn-view.py" --apply --server-dir "$server_dir"; then
    log 'BlueMap map start-pos and inhabited-time settings updated for the fresh world'
  else
    log 'WARNING: BlueMap spawn-view update failed; start-pos may still point at 0,0'
  fi
  if timeout --signal=TERM --kill-after="${RCON_KILL_AFTER}s" "${RCON_CALL_TIMEOUT}s" \
       docker exec "$CONTAINER" rcon-cli 'bluemap reload' >/dev/null 2>&1; then
    log 'BlueMap reloaded to apply the fresh-world map settings'
  else
    log 'WARNING: BlueMap reload failed; fresh map settings apply at the next reload or restart'
  fi
fi

if (( ${#seeds[@]} > 0 )); then
  printf '%s\n' "$(( (index + 1) % ${#seeds[@]} ))" > "$idx_file"
  log "seed for today: $seed"
else
  log 'seeds file empty — fresh random seed'
fi
log 'daily reset complete'
