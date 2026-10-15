#!/usr/bin/env bash
# Isolated mock tests for daily-reset.sh. Never invokes a real Docker daemon.
set -euo pipefail
script_dir="$(cd -- "$(dirname -- "$0")" && pwd)"
script="$script_dir/daily-reset.sh"
tmp="$(mktemp -d)"
trap 'rm -rf -- "$tmp"' EXIT
mkdir -p "$tmp/bin" "$tmp/server" "$tmp/state"
cat > "$tmp/server/server.properties" <<'EOF'
level-name=world
level-seed=old
motd=test
EOF
printf '11\n22\n' > "$tmp/seeds"
cat > "$tmp/bin/date" <<'EOF'
#!/bin/sh
case "$*" in *+%F*) echo 2026-10-10;; *) echo '2026-10-10 04:00:00 UTC';; esac
EOF
cat > "$tmp/bin/docker" <<'EOF'
#!/bin/bash
printf '%s\n' "$*" >> "$CALLS"
case "$1 $2" in
  'inspect --format')
    case "$3" in
      *Mounts*) echo "bind $SERVER_DIR /data";;
      *Running*) echo true;;
    esac;;
  'wait minecraft') [[ "${WAIT_FAIL:-0}" == 0 ]] || exit 1; echo "${WAIT_EXIT:-0}";;
  'exec -i') cat >/dev/null; [[ "${MANAGED_START_FAIL:-0}" == 0 ]];;
  'exec minecraft')
    if [[ "${HANG_RCON:-}" == 'list' && "$3 $4" == 'rcon-cli minecraft:list' ]] ||
       [[ "${HANG_RCON:-}" == 'set' && "$4" == *'players_sleeping_percentage 50'* ]] ||
       [[ "${HANG_RCON:-}" == 'query' && "$4" == *'players_sleeping_percentage'* && "$4" != *' 50'* ]]; then
      sleep 30
    fi
    case "$3 $4" in
      'rcon-cli save-all flush') [[ "${FLUSH_FAIL:-0}" == 0 ]];;
      'rcon-cli stop')
        [[ "${STOP_FAIL:-0}" == 0 ]] || exit 1
        if [[ "${TEST_KIT_REPLACE_DURING_STOP:-0}" == symlink ]]; then
          rm -f -- "$SERVER_DIR/plugins/AwepeepsSpawnKit/issued-kits.yml"
          ln -s "$tmp/kit-target" "$SERVER_DIR/plugins/AwepeepsSpawnKit/issued-kits.yml"
        fi
        if [[ "${TEST_KIT_DIR_REPLACE_DURING_STOP:-0}" == symlink ]]; then
          rm -rf -- "$SERVER_DIR/plugins/AwepeepsSpawnKit"
          ln -s "$tmp/test-kit-dir-target" "$SERVER_DIR/plugins/AwepeepsSpawnKit"
        fi
        if [[ "${COMPASS_REPLACE_DURING_STOP:-0}" == symlink ]]; then
          rm -f -- "$SERVER_DIR/plugins/AwepeepsBlueMapCompass/banner-markers.yml"
          ln -s "$tmp/kit-target" "$SERVER_DIR/plugins/AwepeepsBlueMapCompass/banner-markers.yml"
        fi;;
      'rcon-cli minecraft:list') [[ "${UNHEALTHY:-0}" == 0 ]];;
      'rcon-cli bluemap purge'*)
        map_id="${4#bluemap purge }"
        if [[ "${BLUEMAP_LOADING:-0}" == 1 ]]; then
          count_file="$STATE_DIR/bluemap-attempt-$map_id"
          count=0; [[ ! -f "$count_file" ]] || read -r count < "$count_file"
          count=$((count + 1)); printf '%s\n' "$count" > "$count_file"
          if (( count <= ${BLUEMAP_LOADING_ATTEMPTS:-1} )); then echo "BlueMap is still loading"; exit 0; fi
        fi
        if [[ "${BLUEMAP_UNKNOWN:-}" == "$map_id" ]]; then echo "Unknown map $map_id"; exit 0; fi
        if [[ "${BLUEMAP_ACK:-}" == prefix ]]; then printf 'Scheduled a new task to purge map %s_other\n' "$map_id"; exit 0; fi
        printf '\033[32m§x§F§F§0§0§0§0Scheduled a new task to purge map %s\033[0m\r\nUse /bluemap to see the progress\r\n' "$map_id";;
      'rcon-cli execute in minecraft:overworld run forceload query')
        if [[ "${FORCELOAD_EXISTS:-0}" == 1 ]]; then
          echo 'Some chunks are marked for force loading in minecraft:overworld'
        else
          echo 'No force loaded chunks were found in minecraft:overworld'
        fi;;
      'rcon-cli execute in minecraft:overworld run forceload add '*)
        if [[ "${SPAWN_KIT_SETUP_COMPLETE:-0}" == 1 ]]; then
          mkdir -p "$SERVER_DIR/plugins/AwepeepsSpawnKit"
          printf 'worlds:\n  test:\n    setup-complete: true\n' > "$SERVER_DIR/plugins/AwepeepsSpawnKit/issued-kits.yml"
        elif [[ "${SPAWN_KIT_CHEST_ONLY:-0}" == 1 ]]; then
          mkdir -p "$SERVER_DIR/plugins/AwepeepsSpawnKit"
          printf 'worlds:\n  test:\n    issued: true\n' > "$SERVER_DIR/plugins/AwepeepsSpawnKit/issued-kits.yml"
        fi
        if [[ "${SPAWN_KIT_BAD_ADD_ACK:-0}" == 1 ]]; then echo 'Invalid chunk area'; else echo 'Marked 36 chunks in minecraft:overworld to be force loaded'; fi;;
      'rcon-cli execute in minecraft:overworld run forceload remove '*)
        [[ "${SPAWN_KIT_REMOVE_FAIL:-0}" == 0 ]] || exit 1
        echo 'Unmarked 36 chunks in minecraft:overworld for force loading';;
      'rcon-cli execute'*)
        case "$4" in
          *'players_sleeping_percentage 50'*) [[ "${GAMERULE_SET_FAIL:-}" == '' || "$4" != *"$GAMERULE_SET_FAIL"* ]];;
          *'players_sleeping_percentage'*)
            [[ "${GAMERULE_VERIFY_FAIL:-}" == '' || "$4" != *"$GAMERULE_VERIFY_FAIL"* ]] || { echo 49; exit 0; }
        echo 50;;
          *) exit 3;;
        esac;;
      *) exit 3;;
    esac;;
  *) exit 3;;
esac
EOF
chmod +x "$tmp/bin/date" "$tmp/bin/docker"
cat > "$tmp/bin/rm" <<'EOF'
#!/bin/bash
if [[ "${FAIL_WORLD_RM:-0}" == 1 ]]; then
  for argument in "$@"; do
    [[ "$argument" != "$SERVER_DIR/world" ]] || exit 1
  done
fi
exec /bin/rm "$@"
EOF
chmod +x "$tmp/bin/rm"
export PATH="$tmp/bin:$PATH" CALLS="$tmp/calls" SERVER_DIR="$tmp/server"
export CONTAINER=minecraft SEEDS_FILE="$tmp/seeds" STATE_DIR="$tmp/state"
export RESET_UNTIL=2026-11-28
export PREWIPE_BACKUP=0
export READINESS_TIMEOUT=1 READINESS_INTERVAL=1
export MCSM_NODE_ID=0123456789abcdef0123456789abcdef
export MCSM_INSTANCE_UUID=abcdef0123456789abcdef0123456789
export script
export tmp
failures=0
check() { local name="$1"; shift; if "$@"; then printf 'ok - %s\n' "$name"; else printf 'not ok - %s\n' "$name"; cat "$tmp/last-error" 2>/dev/null || true; failures=$((failures+1)); fi; }
run() { : > "$CALLS"; env "$@" bash "$script" >/dev/null 2>"$tmp/last-error"; }
run_default_prebackup() { : > "$CALLS"; env -u PREWIPE_BACKUP bash "$script" >/dev/null 2>"$tmp/last-error"; }
has() { grep -Fq -- "$1" "$CALLS"; }
export -f run run_default_prebackup has
check expiry_no_docker bash -c 'run RESET_UNTIL=2026-01-01 && [[ ! -s "$CALLS" ]]'
check expiry_keeps_test_kit_state bash -c 'mkdir -p "$SERVER_DIR/plugins/AwepeepsSpawnKit"; printf tombstone > "$SERVER_DIR/plugins/AwepeepsSpawnKit/issued-kits.yml"; run RESET_UNTIL=2026-01-01 && [[ $(cat "$SERVER_DIR/plugins/AwepeepsSpawnKit/issued-kits.yml") == tombstone ]] && [[ ! -s "$CALLS" ]]; rm -rf "$SERVER_DIR/plugins"'
check expiry_keeps_compass_markers bash -c 'mkdir -p "$SERVER_DIR/plugins/AwepeepsBlueMapCompass"; printf marker > "$SERVER_DIR/plugins/AwepeepsBlueMapCompass/banner-markers.yml"; run RESET_UNTIL=2026-01-01 && [[ $(cat "$SERVER_DIR/plugins/AwepeepsBlueMapCompass/banner-markers.yml") == marker ]] && [[ ! -s "$CALLS" ]]; rm -rf "$SERVER_DIR/plugins"'
check successful_order bash -c 'run && grep -q "wait minecraft" "$CALLS" && grep -q "exec minecraft rcon-cli save-all flush" "$CALLS" && grep -q "exec minecraft rcon-cli stop" "$CALLS" && grep -q "exec -i mcsm-web node" "$CALLS" && grep -q "rcon-cli minecraft:list" "$CALLS" && [[ $(grep -c "players_sleeping_percentage 50" "$CALLS") == 3 ]] && grep -qx level-seed=11 "$SERVER_DIR/server.properties" && grep -qx 1 "$STATE_DIR/seed-index"'
check spawn_kit_loads_then_removes_bounded_area bash -c 'mkdir -p "$SERVER_DIR/plugins/AwepeepsSpawnKit"; printf "spawn-kit:\n  enabled: true\n  house:\n    enabled: true\n" > "$SERVER_DIR/plugins/AwepeepsSpawnKit/config.yml"; run SPAWN_KIT_SETUP_COMPLETE=1 && grep -Fq "forceload add -36 -36 36 36" "$CALLS" && grep -Fq "forceload remove -36 -36 36 36" "$CALLS" && grep -Eq "setup-complete:[[:space:]]*true" "$SERVER_DIR/plugins/AwepeepsSpawnKit/issued-kits.yml"; rm -rf "$SERVER_DIR/plugins"'
check spawn_kit_chest_only_waits_for_issue bash -c 'mkdir -p "$SERVER_DIR/plugins/AwepeepsSpawnKit"; printf "spawn-kit:\n  enabled: true\n  house:\n    enabled: false\n    chest:\n      enabled: true\n" > "$SERVER_DIR/plugins/AwepeepsSpawnKit/config.yml"; run SPAWN_KIT_CHEST_ONLY=1 SPAWN_KIT_SETUP_TIMEOUT=5 && grep -Eq "issued:[[:space:]]*true" "$SERVER_DIR/plugins/AwepeepsSpawnKit/issued-kits.yml" && grep -Fq "forceload remove -36 -36 36 36" "$CALLS"; rm -rf "$SERVER_DIR/plugins"'
check spawn_kit_load_timeout_still_cleans_ticket bash -c 'mkdir -p "$SERVER_DIR/plugins/AwepeepsSpawnKit"; printf "spawn-kit:\n  enabled: true\n  house:\n    enabled: true\n" > "$SERVER_DIR/plugins/AwepeepsSpawnKit/config.yml"; run SPAWN_KIT_SETUP_TIMEOUT=2 && grep -Fq "forceload add -36 -36 36 36" "$CALLS" && grep -Fq "forceload remove -36 -36 36 36" "$CALLS"; rm -rf "$SERVER_DIR/plugins"'
check spawn_kit_bad_add_ack_removes_ticket bash -c 'mkdir -p "$SERVER_DIR/plugins/AwepeepsSpawnKit"; printf "spawn-kit:\n  enabled: true\n  house:\n    enabled: true\n" > "$SERVER_DIR/plugins/AwepeepsSpawnKit/config.yml"; ! run SPAWN_KIT_BAD_ADD_ACK=1 && grep -Fq "forceload remove -36 -36 36 36" "$CALLS"; rm -rf "$SERVER_DIR/plugins"'
check spawn_kit_preserves_existing_force_tickets bash -c 'mkdir -p "$SERVER_DIR/plugins/AwepeepsSpawnKit"; printf "spawn-kit:\n  enabled: true\n  house:\n    enabled: true\n" > "$SERVER_DIR/plugins/AwepeepsSpawnKit/config.yml"; run FORCELOAD_EXISTS=1 && grep -q "forceload query" "$CALLS" && ! grep -q "forceload add\|forceload remove" "$CALLS"; rm -rf "$SERVER_DIR/plugins"'
check spawn_kit_disabled_features_skip_loading bash -c 'mkdir -p "$SERVER_DIR/plugins/AwepeepsSpawnKit"; printf "spawn-kit:\n  enabled: true\n  spawn-marker:\n    enabled: false\n  house:\n    enabled: false\n    chest:\n      enabled: false\n" > "$SERVER_DIR/plugins/AwepeepsSpawnKit/config.yml"; run && ! grep -q "forceload" "$CALLS"; rm -rf "$SERVER_DIR/plugins"'
check spawn_kit_load_bounds_validated_before_stop bash -c '! run SPAWN_KIT_LOAD_RADIUS=41 && ! has "wait minecraft"; ! run SPAWN_KIT_LOAD_X=999999999 && ! has "wait minecraft"; ! run SPAWN_KIT_LOAD_X=29999984 && ! has "wait minecraft"'
check test_kit_issuance_cleared_after_world_reset bash -c 'mkdir -p "$SERVER_DIR/plugins/AwepeepsSpawnKit"; printf tombstone > "$SERVER_DIR/plugins/AwepeepsSpawnKit/issued-kits.yml"; run && [[ ! -e "$SERVER_DIR/plugins/AwepeepsSpawnKit/issued-kits.yml" ]]'
check bluemap_purge_success_before_seed_advance bash -c 'mkdir -p "$SERVER_DIR/plugins/BlueMap"; printf 0 > "$STATE_DIR/seed-index"; run && [[ $(grep -c "bluemap purge" "$CALLS") == 3 ]] && grep -qx 1 "$STATE_DIR/seed-index"; rm -rf "$SERVER_DIR/plugins"'
check bluemap_wrong_prefix_ack_rejected bash -c 'mkdir -p "$SERVER_DIR/plugins/BlueMap"; printf 0 > "$STATE_DIR/seed-index"; ! run BLUEMAP_ACK=prefix && grep -qx 0 "$STATE_DIR/seed-index"; rm -rf "$SERVER_DIR/plugins"'
check bluemap_invalid_map_id_before_shutdown bash -c 'mkdir -p "$SERVER_DIR/plugins/BlueMap"; : > "$CALLS"; ! run BLUEMAP_MAPS="world,../other" && ! grep -q "wait minecraft\|rcon-cli stop" "$CALLS"; rm -rf "$SERVER_DIR/plugins"'
check bluemap_retries_startup_loading bash -c 'mkdir -p "$SERVER_DIR/plugins/BlueMap"; printf 0 > "$STATE_DIR/seed-index"; run BLUEMAP_LOADING=1 BLUEMAP_LOADING_ATTEMPTS=2 READINESS_INTERVAL=1 BLUEMAP_PURGE_TIMEOUT=5 && [[ $(grep -c "bluemap purge world$" "$CALLS") == 3 ]] && grep -qx 1 "$STATE_DIR/seed-index"; rm -rf "$SERVER_DIR/plugins"'
check bluemap_unknown_map_blocks_seed_advance bash -c 'mkdir -p "$SERVER_DIR/plugins/BlueMap"; printf 0 > "$STATE_DIR/seed-index"; ! run BLUEMAP_UNKNOWN=world_the_nether && grep -qx 0 "$STATE_DIR/seed-index"; rm -rf "$SERVER_DIR/plugins"'
check bluemap_loading_timeout_blocks_seed_advance bash -c 'mkdir -p "$SERVER_DIR/plugins/BlueMap"; printf 0 > "$STATE_DIR/seed-index"; ! run BLUEMAP_LOADING=1 BLUEMAP_LOADING_ATTEMPTS=100 BLUEMAP_PURGE_TIMEOUT=1 READINESS_INTERVAL=1 && grep -qx 0 "$STATE_DIR/seed-index"; rm -rf "$SERVER_DIR/plugins"'
check removed_container_zero_exit bash -c 'run WAIT_EXIT=0'
check nonzero_exit_refuses_wipe bash -c 'sed -i "s/^level-seed=.*/level-seed=old/" "$SERVER_DIR/server.properties"; ! run WAIT_EXIT=137 && grep -qx level-seed=old "$SERVER_DIR/server.properties" && ! has "exec -i mcsm-web"'
check wait_failure_refuses_wipe bash -c '! run WAIT_FAIL=1'
check flush_failure_refuses_wipe bash -c '! run FLUSH_FAIL=1'
check stop_failure_refuses_wipe bash -c '! run STOP_FAIL=1'
check managed_start_failure_no_advance bash -c 'printf 0 > "$STATE_DIR/seed-index"; ! run MANAGED_START_FAIL=1 && grep -qx 0 "$STATE_DIR/seed-index"'
check unhealthy_no_advance bash -c 'printf 0 > "$STATE_DIR/seed-index"; ! run UNHEALTHY=1 && grep -qx 0 "$STATE_DIR/seed-index" && ! grep -q "players_sleeping_percentage 50" "$CALLS"; ! run HANG_RCON=list READINESS_TIMEOUT=2 READINESS_INTERVAL=1 RCON_CALL_TIMEOUT=1 RCON_KILL_AFTER=1 && grep -qx 0 "$STATE_DIR/seed-index"'
check gamerule_set_failure_no_advance bash -c 'printf 0 > "$STATE_DIR/seed-index"; ! run GAMERULE_SET_FAIL=minecraft:the_nether && grep -qx 0 "$STATE_DIR/seed-index"; ! run HANG_RCON=set RCON_CALL_TIMEOUT=1 RCON_KILL_AFTER=1 && grep -qx 0 "$STATE_DIR/seed-index"'
check gamerule_verify_failure_no_advance bash -c 'printf 0 > "$STATE_DIR/seed-index"; ! run GAMERULE_VERIFY_FAIL=minecraft:the_end && grep -qx 0 "$STATE_DIR/seed-index"'
check level_mismatch_refuses_stop bash -c 'sed -i s/level-name=world/level-name=other/ "$SERVER_DIR/server.properties"; ! run && ! has "wait minecraft"; sed -i s/level-name=other/level-name=world/ "$SERVER_DIR/server.properties"'
check world_symlink_refuses_stop bash -c 'ln -s "$tmp/outside" "$SERVER_DIR/world"; ! run && ! has "wait minecraft"; rm "$SERVER_DIR/world"'
check plugins_symlink_refuses_stop bash -c 'ln -s "$tmp/outside" "$SERVER_DIR/plugins"; ! run && ! has "wait minecraft"; rm "$SERVER_DIR/plugins"'
check unsafe_path_refuses_stop bash -c '! run SERVER_DIR=/ && ! has "inspect --format"'
check seed_index_symlink_refuses_stop bash -c 'rm -f "$STATE_DIR/seed-index"; ln -s "$tmp/outside" "$STATE_DIR/seed-index"; ! run && ! has "wait minecraft"; rm "$STATE_DIR/seed-index"'
check lock_symlink_refuses_stop bash -c 'rm -f "$STATE_DIR/lifecycle.lock"; ln -s "$tmp/outside" "$STATE_DIR/lifecycle.lock"; ! run && ! has "wait minecraft"; rm "$STATE_DIR/lifecycle.lock"'
check lock_hardlink_refuses_stop_without_truncation bash -c 'rm -f "$STATE_DIR/lifecycle.lock"; printf sentinel > "$STATE_DIR/lifecycle.lock"; ln "$STATE_DIR/lifecycle.lock" "$tmp/lock-alias"; ! run && [[ $(cat "$tmp/lock-alias") == sentinel ]] && ! has "wait minecraft"; rm -f "$STATE_DIR/lifecycle.lock" "$tmp/lock-alias"'
check state_symlink_refuses_early bash -c 'mv "$STATE_DIR" "$tmp/state-real"; ln -s "$tmp/state-real" "$STATE_DIR"; ! run && [[ ! -e "$tmp/state-real/lifecycle.lock" ]]; rm "$STATE_DIR"; mv "$tmp/state-real" "$STATE_DIR"'
check leading_zero_index bash -c 'printf 0001 > "$STATE_DIR/seed-index"; run && grep -qx level-seed=22 "$SERVER_DIR/server.properties"'
check compass_marker_state_reset bash -c 'mkdir -p "$SERVER_DIR/plugins/AwepeepsBlueMapCompass"; printf "banner-markers: [old]\n" > "$SERVER_DIR/plugins/AwepeepsBlueMapCompass/banner-markers.yml"; printf keep > "$SERVER_DIR/plugins/AwepeepsBlueMapCompass/other-state.yml"; run && [[ ! -e "$SERVER_DIR/plugins/AwepeepsBlueMapCompass/banner-markers.yml" ]] && [[ $(cat "$SERVER_DIR/plugins/AwepeepsBlueMapCompass/other-state.yml") == keep ]]'
check compass_marker_symlink_refuses_stop bash -c 'mkdir -p "$SERVER_DIR/plugins/AwepeepsBlueMapCompass"; printf target > "$tmp/marker-target"; ln -s "$tmp/marker-target" "$SERVER_DIR/plugins/AwepeepsBlueMapCompass/banner-markers.yml"; ! run && ! has "wait minecraft"; rm -rf "$SERVER_DIR/plugins"'
check compass_marker_hardlink_refuses_stop bash -c 'mkdir -p "$SERVER_DIR/plugins/AwepeepsBlueMapCompass"; printf marker > "$tmp/marker-hardlink"; ln "$tmp/marker-hardlink" "$SERVER_DIR/plugins/AwepeepsBlueMapCompass/banner-markers.yml"; ! run && ! has "wait minecraft"; rm -rf "$SERVER_DIR/plugins"'
check compass_marker_reverified_before_wipe bash -c 'mkdir -p "$SERVER_DIR/plugins/AwepeepsBlueMapCompass" "$SERVER_DIR/world"; printf marker > "$SERVER_DIR/plugins/AwepeepsBlueMapCompass/banner-markers.yml"; printf preserve > "$SERVER_DIR/world/sentinel"; ! run COMPASS_REPLACE_DURING_STOP=symlink && [[ -L "$SERVER_DIR/plugins/AwepeepsBlueMapCompass/banner-markers.yml" ]] && [[ $(cat "$SERVER_DIR/world/sentinel") == preserve ]] && ! grep -q "exec -i mcsm-web" "$CALLS"; rm -rf "$SERVER_DIR/plugins" "$SERVER_DIR/world"'
check world_delete_failure_preserves_compass_markers bash -c 'mkdir -p "$SERVER_DIR/plugins/AwepeepsBlueMapCompass" "$SERVER_DIR/world"; printf marker > "$SERVER_DIR/plugins/AwepeepsBlueMapCompass/banner-markers.yml"; printf preserve > "$SERVER_DIR/world/sentinel"; ! run FAIL_WORLD_RM=1 && [[ $(cat "$SERVER_DIR/plugins/AwepeepsBlueMapCompass/banner-markers.yml") == marker ]] && [[ $(cat "$SERVER_DIR/world/sentinel") == preserve ]] && ! grep -q "exec -i mcsm-web" "$CALLS"; rm -rf "$SERVER_DIR/plugins" "$SERVER_DIR/world"'
check test_kit_state_symlink_refuses_stop bash -c 'mkdir -p "$SERVER_DIR/plugins/AwepeepsSpawnKit"; printf target > "$tmp/kit-target"; ln -s "$tmp/kit-target" "$SERVER_DIR/plugins/AwepeepsSpawnKit/issued-kits.yml"; ! run && ! has "wait minecraft"; rm -rf "$SERVER_DIR/plugins"'
check test_kit_state_hardlink_refuses_stop bash -c 'mkdir -p "$SERVER_DIR/plugins/AwepeepsSpawnKit"; printf tombstone > "$tmp/kit-hardlink"; ln "$tmp/kit-hardlink" "$SERVER_DIR/plugins/AwepeepsSpawnKit/issued-kits.yml"; ! run && ! has "wait minecraft"; rm -rf "$SERVER_DIR/plugins"'
check test_kit_state_reverified_before_wipe bash -c 'mkdir -p "$SERVER_DIR/plugins/AwepeepsSpawnKit" "$SERVER_DIR/world"; printf tombstone > "$SERVER_DIR/plugins/AwepeepsSpawnKit/issued-kits.yml"; printf preserve > "$SERVER_DIR/world/sentinel"; ! run TEST_KIT_REPLACE_DURING_STOP=symlink && [[ -L "$SERVER_DIR/plugins/AwepeepsSpawnKit/issued-kits.yml" ]] && [[ $(cat "$SERVER_DIR/world/sentinel") == preserve ]] && ! grep -q "exec -i mcsm-web" "$CALLS"; rm -rf "$SERVER_DIR/plugins" "$SERVER_DIR/world"'
check world_delete_failure_preserves_test_kit_state bash -c 'mkdir -p "$SERVER_DIR/plugins/AwepeepsSpawnKit" "$SERVER_DIR/world"; printf tombstone > "$SERVER_DIR/plugins/AwepeepsSpawnKit/issued-kits.yml"; printf preserve > "$SERVER_DIR/world/sentinel"; ! run FAIL_WORLD_RM=1 && [[ $(cat "$SERVER_DIR/plugins/AwepeepsSpawnKit/issued-kits.yml") == tombstone ]] && [[ $(cat "$SERVER_DIR/world/sentinel") == preserve ]] && ! grep -q "exec -i mcsm-web" "$CALLS"; rm -rf "$SERVER_DIR/plugins" "$SERVER_DIR/world"'
check test_kit_dir_symlink_refuses_stop bash -c 'mkdir -p "$SERVER_DIR/plugins" "$tmp/test-kit-dir-target"; ln -s "$tmp/test-kit-dir-target" "$SERVER_DIR/plugins/AwepeepsSpawnKit"; ! run && ! has "wait minecraft"; rm -rf "$SERVER_DIR/plugins"'
check test_kit_dir_reverified_before_wipe bash -c 'mkdir -p "$SERVER_DIR/plugins/AwepeepsSpawnKit" "$SERVER_DIR/world" "$tmp/test-kit-dir-target"; printf tombstone > "$SERVER_DIR/plugins/AwepeepsSpawnKit/issued-kits.yml"; printf preserve > "$SERVER_DIR/world/sentinel"; ! run TEST_KIT_DIR_REPLACE_DURING_STOP=symlink && [[ -L "$SERVER_DIR/plugins/AwepeepsSpawnKit" ]] && [[ $(cat "$SERVER_DIR/world/sentinel") == preserve ]] && ! grep -q "exec -i mcsm-web" "$CALLS"; rm -rf "$SERVER_DIR/plugins" "$SERVER_DIR/world"'
mkdir -p "$tmp/reset-bin"
cp "$script" "$tmp/reset-bin/daily-reset.sh"
cp "$script_dir/mcsm-start.js" "$tmp/reset-bin/mcsm-start.js"
cat > "$tmp/reset-bin/backup.sh" <<'EOF'
#!/usr/bin/env bash
[[ "${BACKUP_LOCK_HELD:-}" == 1 ]] || exit 9
if [[ "${BACKUP_REQUIRE_TEST_KIT:-0}" == 1 ]]; then
  [[ -f "$SERVER_DIR/plugins/AwepeepsSpawnKit/issued-kits.yml" ]] || exit 11
  cp -- "$SERVER_DIR/plugins/AwepeepsSpawnKit/issued-kits.yml" "$BACKUP_TEST_KIT_SNAPSHOT"
fi
printf 'backup\n' >> "$BACKUP_CALLS"
[[ "${BACKUP_FAIL:-0}" == 0 ]]
EOF
chmod +x "$tmp/reset-bin/backup.sh"
script="$tmp/reset-bin/daily-reset.sh"; export script BACKUP_CALLS="$tmp/backup-calls"
check prewipe_backup_failure_aborts_before_stop bash -c 'before=$(grep "^level-seed=" "$SERVER_DIR/server.properties"); : > "$CALLS"; ! run PREWIPE_BACKUP=1 BACKUP_FAIL=1 && grep -qx backup "$BACKUP_CALLS" && ! grep -q "wait minecraft\|rcon-cli stop" "$CALLS" && grep -qx "$before" "$SERVER_DIR/server.properties"'
check prewipe_backup_default_runs_under_lock bash -c 'rm -f "$BACKUP_CALLS"; run_default_prebackup && grep -qx backup "$BACKUP_CALLS" && grep -q "rcon-cli stop" "$CALLS"'
check test_kit_state_is_backed_up_before_reset bash -c 'mkdir -p "$SERVER_DIR/plugins/AwepeepsSpawnKit"; printf tombstone > "$SERVER_DIR/plugins/AwepeepsSpawnKit/issued-kits.yml"; run PREWIPE_BACKUP=1 BACKUP_REQUIRE_TEST_KIT=1 BACKUP_TEST_KIT_SNAPSHOT="$tmp/test-kit-backup" && [[ $(cat "$tmp/test-kit-backup") == tombstone ]] && [[ ! -e "$SERVER_DIR/plugins/AwepeepsSpawnKit/issued-kits.yml" ]]; rm -rf "$SERVER_DIR/plugins"'
if (( failures )); then printf '%d test(s) failed\n' "$failures" >&2; exit 1; fi
printf 'all daily-reset mock tests passed\n'
