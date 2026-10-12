#!/usr/bin/env bash
# Isolated backup/restore mocks. Does not contact a Docker daemon.
set -euo pipefail
root="$(cd -- "$(dirname -- "$0")/.." && pwd)"; tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/bin" "$tmp/server/world/dimensions/minecraft/overworld/region" "$tmp/server/world/dimensions/minecraft/the_nether/region" "$tmp/server/world/dimensions/minecraft/the_end/region" "$tmp/state" "$tmp/backups"
mkdir -p "$tmp/server/plugins/AwepeepsBlueMapCompass" "$tmp/server/plugins/AwepeepsSpawnKit"
printf 'banner-markers: []\n' > "$tmp/server/plugins/AwepeepsBlueMapCompass/banner-markers.yml"
printf 'issued: true\n' > "$tmp/server/plugins/AwepeepsSpawnKit/issued-kits.yml"
echo level-name=world > "$tmp/server/server.properties"; echo level > "$tmp/server/world/level.dat"; echo region > "$tmp/server/world/dimensions/minecraft/overworld/region/r.0.0.mca"; echo region > "$tmp/server/world/dimensions/minecraft/the_nether/region/r.0.0.mca"; echo region > "$tmp/server/world/dimensions/minecraft/the_end/region/r.0.0.mca"
cat > "$tmp/bin/docker" <<'SH'
#!/bin/bash
echo "$*" >> "$CALLS"
if [[ "$1 $2" == 'inspect --format' ]]; then
 case "$3" in *Mounts*) echo "bind $SERVER_DIR /data";; *Running*) echo true;; *Image*) echo sha256:mock;; esac; exit 0
fi
if [[ "$1 $2 $3" == 'exec minecraft rcon-cli' ]]; then
 [[ "${FAIL_RCON:-}" != "$4" ]] || exit 1
 [[ "$4" != save-off ]] || touch "$SAVE_OFF"
 [[ "$4" != save-on ]] || { [[ "${FAIL_RCON:-}" != save-on ]] && touch "$SAVE_ON"; }
fi
SH
chmod +x "$tmp/bin/docker"
export PATH="$tmp/bin:$PATH" SERVER_DIR="$tmp/server" CONTAINER=minecraft BACKUP_ROOT="$tmp/backups" STATE_DIR="$tmp/state" CALLS="$tmp/calls" SAVE_OFF="$tmp/off" SAVE_ON="$tmp/on"
run() { sleep 1; rm -f "$SAVE_OFF" "$SAVE_ON"; : > "$CALLS"; env "$@" bash "$root/automation/backup.sh" >/dev/null || { cat "$tmp/error" 2>/dev/null; return 1; } }
export root tmp
export -f run
check() { name="$1"; shift; if "$@"; then echo "ok - $name"; else echo "not ok - $name"; exit 1; fi; }
check successful_archive run
archive=("$BACKUP_ROOT"/daily/world-*.tar.gz); [[ -f "${archive[0]}" && -f "$SAVE_ON" && "$(stat -c %a "${archive[0]}")" == 600 ]] || exit 1
export ARCHIVE="${archive[0]}"
check nested_dimensions_and_verify bash -c 'tar -tzf "$ARCHIVE" | grep -q world/dimensions/minecraft/the_end/region/ && bash "$root/automation/backup-verify.sh" "$ARCHIVE" >/dev/null'
check compass_plugin_data_included bash -c 'tar -tzf "$ARCHIVE" | grep -q plugins/AwepeepsBlueMapCompass/banner-markers.yml'
check spawn_kit_state_included bash -c 'tar -tzf "$ARCHIVE" | grep -q plugins/AwepeepsSpawnKit/issued-kits.yml'
check retention_deduplicates_same_day bash -c 'stamp=$(basename "$ARCHIVE" .tar.gz); day=${stamp#world-}; day=${day%-*}; cp "$ARCHIVE" "$BACKUP_ROOT/daily/world-${day}-000001.tar.gz"; sleep 1; run && [[ $(find "$BACKUP_ROOT/daily" -maxdepth 1 -name "world-*.tar.gz" | wc -l) == 1 ]]'
archive=("$BACKUP_ROOT"/daily/world-*.tar.gz); ARCHIVE="${archive[0]}"; export ARCHIVE
check save_off_failure_attempts_restore bash -c '! run FAIL_RCON=save-off && [[ -f "$SAVE_ON" ]]'
check save_on_cleanup_failure_fails_backup bash -c '! run FAIL_RCON=save-on && [[ ! -f "$SAVE_ON" ]]'
check partial_archive_failure_save_on bash -c 'mkdir -p "$tmp/bin"; printf "#!/bin/sh\\nexit 1\\n" > "$tmp/bin/tar"; chmod +x "$tmp/bin/tar"; ! run && [[ -f "$SAVE_ON" ]] && ! compgen -G "$BACKUP_ROOT/daily/.world-*.partial.*"; rm "$tmp/bin/tar"'
check symlink_world_rejected bash -c 'mv "$SERVER_DIR/world" "$tmp/world-real"; ln -s "$tmp/world-real" "$SERVER_DIR/world"; ! run && ! grep -q "exec minecraft" "$CALLS"; rm "$SERVER_DIR/world"; mv "$tmp/world-real" "$SERVER_DIR/world"'
check spawn_kit_symlink_rejected bash -c 'rm -rf "$SERVER_DIR/plugins/AwepeepsSpawnKit"; ln -s "$tmp/outside" "$SERVER_DIR/plugins/AwepeepsSpawnKit"; ! run && ! grep -q "exec minecraft" "$CALLS"; rm "$SERVER_DIR/plugins/AwepeepsSpawnKit"'
check malformed_retention_rejected bash -c '! run KEEP_DAILY=1x'
check verify_traversal_rejected bash -c 'python3 - "$ARCHIVE" "$tmp/bad.tar.gz" <<"PY"
import sys,tarfile
with tarfile.open(sys.argv[2],"w:gz") as t:
 import io
 b=b"x"; i=tarfile.TarInfo("../escape"); i.size=len(b); t.addfile(i,io.BytesIO(b))
PY
! bash "$root/automation/backup-verify.sh" "$tmp/bad.tar.gz" >/dev/null 2>&1'
check verify_missing_world_rejected bash -c 'python3 - "$ARCHIVE" "$tmp/no-world.tar.gz" <<"PY"
import sys,tarfile
with tarfile.open(sys.argv[1],"r:gz") as src, tarfile.open(sys.argv[2],"w:gz") as dst:
 for m in src:
  if m.name != "world/level.dat": dst.addfile(m,src.extractfile(m) if m.isfile() else None)
PY
! bash "$root/automation/backup-verify.sh" "$tmp/no-world.tar.gz" >/dev/null 2>&1'
for dimension in overworld the_nether the_end; do
 check "verify_missing_${dimension}_rejected" env MISSING_DIM="$dimension" bash -c 'python3 - "$ARCHIVE" "$tmp/no-$MISSING_DIM.tar.gz" "$MISSING_DIM" <<"PY"
import sys,tarfile
missing="world/dimensions/minecraft/"+sys.argv[3]
with tarfile.open(sys.argv[1],"r:gz") as src, tarfile.open(sys.argv[2],"w:gz") as dst:
 for m in src:
  if not m.name.startswith(missing+"/"): dst.addfile(m,src.extractfile(m) if m.isfile() else None)
PY
! bash "$root/automation/backup-verify.sh" "$tmp/no-$MISSING_DIM.tar.gz" >/dev/null 2>&1'
done
check backup_lock_hardlink_refused_without_truncation bash -c 'printf sentinel > "$STATE_DIR/lifecycle.lock"; ln "$STATE_DIR/lifecycle.lock" "$tmp/lock-alias"; ! run && [[ $(cat "$tmp/lock-alias") == sentinel ]] && ! grep -q "exec minecraft" "$CALLS"; rm -f "$STATE_DIR/lifecycle.lock" "$tmp/lock-alias"'
check daily_retention_keeps_seven_distinct_dates bash -c 'for d in 20260101 20260102 20260103 20260104 20260105 20260106 20260107 20260108 20260109; do cp "$ARCHIVE" "$BACKUP_ROOT/daily/world-$d-120000.tar.gz"; done; run && [[ $(find "$BACKUP_ROOT/daily" -maxdepth 1 -type f -name "world-*.tar.gz" | wc -l) == 7 ]]'
archive=("$BACKUP_ROOT"/daily/world-*.tar.gz); ARCHIVE="${archive[0]}"; export ARCHIVE
check weekly_retention_keeps_four_distinct_weeks bash -c '[[ $(TZ=UTC date +%u) == 7 ]] || exit 0; for d in 20260830 20260906 20260913 20260920 20260927 20261004; do cp "$ARCHIVE" "$BACKUP_ROOT/weekly/world-$d-120000.tar.gz"; done; run && [[ $(find "$BACKUP_ROOT/weekly" -maxdepth 1 -type f -name "world-*.tar.gz" | wc -l) == 4 ]]'
check scheduled_inactive_phase_noops bash -c ': > "$CALLS"; RESET_UNTIL=2000-01-01 BACKUP_PHASE=test bash "$root/automation/backup-scheduled.sh" >/dev/null && [[ ! -s "$CALLS" ]]; : > "$CALLS"; RESET_UNTIL=9999-01-01 BACKUP_PHASE=live bash "$root/automation/backup-scheduled.sh" >/dev/null && [[ ! -s "$CALLS" ]]'
check scheduled_active_phase_runs_backup bash -c 'sleep 1; : > "$CALLS"; RESET_UNTIL=9999-01-01 BACKUP_PHASE=test bash "$root/automation/backup-scheduled.sh" >/dev/null && grep -q "exec minecraft rcon-cli save-off" "$CALLS"'
printf 'all backup mock tests passed\n'
