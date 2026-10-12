#!/usr/bin/env bash
# Portable, live-safe Minecraft backup. Run on the host that runs the server
# container, as the user that owns the instance data directory.
#
# Reads its configuration from the environment (see .env.example). Every value
# has a safe default except SERVER_DIR, which must point at the real instance
# data directory used as the container's /data bind-mount source.
set -euo pipefail
umask 077

CONTAINER="${CONTAINER:-minecraft}"
SERVER_DIR="${SERVER_DIR:-}"
DATA_DEST="${DATA_DEST:-/data}"
BACKUP_ROOT="${BACKUP_ROOT:-/srv/minecraft/backups}"
STATE_DIR="${STATE_DIR:-/srv/minecraft/.reset-state}"
BACKUP_TIMEZONE="${BACKUP_TIMEZONE:-UTC}"
KEEP_DAILY="${KEEP_DAILY:-7}"
KEEP_WEEKLY="${KEEP_WEEKLY:-4}"
RCON_TIMEOUT="${RCON_TIMEOUT:-20}"
RCON_KILL_AFTER="${RCON_KILL_AFTER:-2}"
# Exact paths that must never be used as SERVER_DIR or BACKUP_ROOT.
PROTECTED_PATHS="${PROTECTED_PATHS:-/ /home /root /srv /mnt /opt /usr /var /etc}"
# Plugin data directories included in the archive when present (relative to SERVER_DIR).
PLUGIN_DATA_DIRS="${PLUGIN_DATA_DIRS:-plugins/AwepeepsBlueMapCompass plugins/AwepeepsSpawnKit}"

die() { echo "backup: $*" >&2; exit 2; }
log() { printf '%s %s\n' "$(TZ="$BACKUP_TIMEZONE" date '+%Y-%m-%d %H:%M:%S %Z')" "$*"; }
path_is_protected() {
  local probe="$1" parent
  for parent in $PROTECTED_PATHS; do [[ "$probe" == "$parent" ]] && return 0; done
  return 1
}
for n in KEEP_DAILY KEEP_WEEKLY RCON_TIMEOUT RCON_KILL_AFTER; do v="${!n}"; [[ "$v" =~ ^[0-9]{1,4}$ ]] || die "$n must be a bounded non-negative integer"; done
(( KEEP_DAILY > 0 && KEEP_DAILY <= 365 && KEEP_WEEKLY > 0 && KEEP_WEEKLY <= 104 && RCON_TIMEOUT > 0 && RCON_KILL_AFTER <= 60 )) || die 'retention or timeout is outside safe bounds'
[[ -n "$SERVER_DIR" && "$SERVER_DIR" != / && ! -L "$SERVER_DIR" && -d "$SERVER_DIR" ]] || die 'SERVER_DIR must be an existing real instance directory'
server_dir="$(realpath -e -- "$SERVER_DIR")"
path_is_protected "$server_dir" && die 'SERVER_DIR resolves to a protected parent'
[[ -f "$server_dir/server.properties" && ! -L "$server_dir/server.properties" ]] || die 'server.properties must be a regular file'
[[ ! -L "$BACKUP_ROOT" ]] || die 'BACKUP_ROOT cannot be a symlink'
backup_root="$(realpath -m -- "$BACKUP_ROOT")"
path_is_protected "$backup_root" && die 'BACKUP_ROOT resolves to a protected parent'
[[ "$backup_root" != "$server_dir" && "$backup_root" != "$server_dir"/* && "$server_dir" != "$backup_root"/* ]] || die 'BACKUP_ROOT and SERVER_DIR must be separate trees'
BACKUP_ROOT="$backup_root"
[[ "$DATA_DEST" == /* && "$DATA_DEST" != / && "$CONTAINER" != -* ]] || die 'invalid DATA_DEST or CONTAINER'
[[ -d "$server_dir/world" && ! -L "$server_dir/world" && "$(realpath -e -- "$server_dir/world")" == "$server_dir/world" ]] || die 'world must be a real directory inside SERVER_DIR'
worlds=(world)
# Modern Paper stores dimensions beneath world/. Older layouts may use siblings.
for w in world_nether world_the_end; do
  [[ ! -L "$server_dir/$w" ]] || die "$w is a symlink"
  if [[ -e "$server_dir/$w" ]]; then
    [[ -d "$server_dir/$w" && "$(realpath -e -- "$server_dir/$w")" == "$server_dir/$w" ]] || die "$w is not contained in SERVER_DIR"
    worlds+=("$w")
  fi
done
[[ ! -L "$server_dir/plugins" ]] || die 'plugins directory is a symlink'
if [[ -e "$server_dir/plugins" ]]; then [[ -d "$server_dir/plugins" && "$(realpath -e -- "$server_dir/plugins")" == "$server_dir/plugins" ]] || die 'plugins resolves outside SERVER_DIR'; fi
plugin_data=()
for rel in $PLUGIN_DATA_DIRS; do
  target="$server_dir/$rel"
  [[ "$rel" != /* && "$rel" != *..* ]] || die "PLUGIN_DATA_DIRS entries must be relative paths inside SERVER_DIR: $rel"
  [[ ! -L "$target" ]] || die "plugin data directory is a symlink: $rel"
  if [[ -e "$target" ]]; then
    [[ -d "$target" && "$(realpath -e -- "$target")" == "$target" ]] || die "plugin data directory must be contained in SERVER_DIR: $rel"
    plugin_data+=("$rel")
  fi
done
[[ ! -L "$STATE_DIR" ]] || die 'STATE_DIR must not be a symlink'
mkdir -p -- "$STATE_DIR" "$BACKUP_ROOT/daily" "$BACKUP_ROOT/weekly"
[[ ! -L "$BACKUP_ROOT" && ! -L "$BACKUP_ROOT/daily" && ! -L "$BACKUP_ROOT/weekly" ]] || die 'backup directories cannot be symlinks'
chmod 700 "$BACKUP_ROOT" "$BACKUP_ROOT/daily" "$BACKUP_ROOT/weekly"
[[ ! -L "$STATE_DIR/lifecycle.lock" ]] || die 'lifecycle lock cannot be a symlink'
if [[ "${BACKUP_LOCK_HELD:-0}" != 1 ]]; then
  lockfile="$STATE_DIR/lifecycle.lock"
  [[ ! -e "$lockfile" || ( -f "$lockfile" && ! -L "$lockfile" && "$(stat -c %h -- "$lockfile")" == 1 ) ]] || die 'lifecycle lock must be a single-link regular file'
  exec 9>>"$lockfile"
  [[ -f "$lockfile" && ! -L "$lockfile" && "$(stat -c %h -- "$lockfile")" == 1 ]] || die 'lifecycle lock changed or is hard-linked'
  flock -n 9 || die 'another lifecycle job (reset or backup) is running'
fi
mounts="$(docker inspect --format '{{range .Mounts}}{{println .Type .Source .Destination}}{{end}}' "$CONTAINER")" || die 'could not inspect container'
grep -Fqx -- "bind $server_dir $DATA_DEST" <<<"$mounts" || die 'container bind mount does not exactly match SERVER_DIR and DATA_DEST'
[[ "$(docker inspect --format '{{.State.Running}}' "$CONTAINER")" == true ]] || die 'container is not running'
command -v timeout >/dev/null || die 'GNU timeout is required'
mc() { timeout --signal=TERM --kill-after="${RCON_KILL_AFTER}s" "${RCON_TIMEOUT}s" docker exec "$CONTAINER" rcon-cli "$@"; }
save_off=false; partial=''; meta_dir=''; weekly_tmp=''
restore_save() { rc=$?; trap - EXIT; [[ -z "$partial" ]] || rm -f -- "$partial"; [[ -z "$meta_dir" ]] || rm -rf -- "$meta_dir"; [[ -z "$weekly_tmp" ]] || rm -f -- "$weekly_tmp"; if [[ "$save_off" == true ]] && ! mc save-on >/dev/null 2>&1; then log 'ERROR: save-on cleanup failed; manual server check required'; (( rc != 0 )) || rc=1; fi; exit "$rc"; }
trap restore_save EXIT
trap 'exit 143' TERM
trap 'exit 130' INT
mc 'say Private backup starting'
save_off=true
mc save-off
mc 'save-all flush'
stamp="$(TZ="$BACKUP_TIMEZONE" date +%Y%m%d-%H%M%S)"
daily="$BACKUP_ROOT/daily/world-$stamp.tar.gz"
[[ ! -e "$daily" && ! -L "$daily" ]] || die 'timestamp collision'
partial="$(mktemp "$BACKUP_ROOT/daily/.world-$stamp.partial.XXXXXX")"
items=("${worlds[@]}" server.properties)
for rel in "${plugin_data[@]}"; do items+=("$rel"); done
paper_jar=''
for candidate in "$server_dir"/paper-*.jar; do
  [[ -e "$candidate" ]] || continue
  [[ -f "$candidate" && ! -L "$candidate" && "$(basename -- "$candidate")" =~ ^paper-[A-Za-z0-9._-]+\.jar$ ]] || die 'unexpected or unsafe Paper jar in SERVER_DIR'
  [[ -z "$paper_jar" ]] || die 'multiple Paper jars found; cannot identify exact runtime'
  paper_jar="$(basename -- "$candidate")"
done
[[ -z "$paper_jar" ]] || items+=("$paper_jar")
image_id="$(docker inspect --format '{{.Image}}' "$CONTAINER")" || die 'could not inspect container image ID'
meta_dir="$(mktemp -d "$BACKUP_ROOT/.backup-meta.XXXXXX")"
{
  printf 'container=%s\n' "$CONTAINER"
  printf 'paper_jar=%s\n' "${paper_jar:-unknown}"
  if [[ -n "$paper_jar" ]]; then printf 'paper_jar_sha256=%s\n' "$(sha256sum "$server_dir/$paper_jar" | cut -d' ' -f1)"; else printf 'paper_jar_sha256=unknown\n'; fi
  printf 'docker_image_id=%s\n' "$image_id"
} > "$meta_dir/backup-metadata.txt"
chmod 600 "$meta_dir/backup-metadata.txt"
tar -C "$server_dir" -czf "$partial" "${items[@]}" -C "$meta_dir" backup-metadata.txt
rm -rf -- "$meta_dir"; meta_dir=''
bash "$(dirname -- "$0")/backup-verify.sh" "$partial"
chmod 600 "$partial"
[[ ! -e "$daily" && ! -L "$daily" ]] || die 'final archive path appeared before publish'
ln -- "$partial" "$daily" || die 'could not atomically publish archive without overwrite'
rm -f -- "$partial"; partial=''
mc save-on; save_off=false
if [[ "$(TZ="$BACKUP_TIMEZONE" date +%u)" == 7 ]]; then
  weekly_final="$BACKUP_ROOT/weekly/world-$stamp.tar.gz"
  [[ ! -e "$weekly_final" && ! -L "$weekly_final" ]] || die 'weekly archive path already exists'
  weekly_tmp="$(mktemp "$BACKUP_ROOT/weekly/.world-$stamp.partial.XXXXXX")"
  cp -- "$daily" "$weekly_tmp" && chmod 600 "$weekly_tmp"
  [[ ! -e "$weekly_final" && ! -L "$weekly_final" ]] || die 'weekly archive path appeared before publish'
  ln -- "$weekly_tmp" "$weekly_final" || die 'could not atomically publish weekly archive without overwrite'
  rm -f -- "$weekly_tmp"
fi
rotate() {
  local dir="$1" keep="$2" mode="$3" file stamp key
  local -A seen=(); local -a remove=(); local count=0
  mapfile -t files < <(find "$dir" -maxdepth 1 -type f -regextype posix-extended -regex '.*/world-[0-9]{8}-[0-9]{6}\.tar\.gz' -printf '%f\n' | sort -r)
  for file in "${files[@]}"; do
    stamp="${file#world-}"; stamp="${stamp%.tar.gz}"
    if [[ "$mode" == daily ]]; then key="${stamp:0:8}"; else key="$(TZ="$BACKUP_TIMEZONE" date -d "${stamp:0:8} ${stamp:9:2}:${stamp:11:2}:00" +%G-%V)"; fi
    if [[ -n "${seen[$key]:-}" ]]; then remove+=("$file"); continue; fi
    seen[$key]=1; ((count+=1)); (( count > keep )) && remove+=("$file")
  done
  for file in "${remove[@]}"; do rm -f -- "$dir/$file"; done
}
rotate "$BACKUP_ROOT/daily" "$KEEP_DAILY" daily; rotate "$BACKUP_ROOT/weekly" "$KEEP_WEEKLY" weekly
log "backup complete: $daily"
