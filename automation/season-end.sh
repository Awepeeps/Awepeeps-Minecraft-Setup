#!/usr/bin/env bash
# season-end.sh — close a season permanently.
#   1) final backup   2) sanitized policy generation   3) private world archive
#   4) stamp the season README with the end date
# Run once at season close. The archive .tar.gz is deliberately gitignored —
# world archives and raw runtime config stay in private local backup storage.
set -euo pipefail
umask 077

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="${REPO_DIR:-$(cd "$HERE/.." && pwd)}"
BACKUP_ROOT="${BACKUP_ROOT:-/srv/minecraft/backups}"
STATE_DIR="${STATE_DIR:-/srv/minecraft/.reset-state}"
SERVER_SLUG="${SERVER_SLUG:-survival}"
SEASON_SLUG="${SEASON_SLUG:-season-1}"
[[ "$SERVER_SLUG" =~ ^[a-z0-9]+(-[a-z0-9]+)*$ && "$SEASON_SLUG" =~ ^[a-z0-9]+(-[a-z0-9]+)*$ ]] || { echo 'season-end: invalid slug' >&2; exit 2; }
[[ -n "${SERVER_DIR:-}" ]] || { echo 'season-end: SERVER_DIR required' >&2; exit 2; }

SEASON_DIR="$REPO_DIR/seasons/$SERVER_SLUG/$SEASON_SLUG"
[[ -f "$SEASON_DIR/README.md" && ! -L "$SEASON_DIR/README.md" ]] || { echo 'season-end: existing season record required' >&2; exit 2; }
[[ "$(realpath -e -- "$SEASON_DIR")" == "$(realpath -e -- "$REPO_DIR")/seasons/$SERVER_SLUG/$SEASON_SLUG" ]] || { echo 'season-end: unsafe season path' >&2; exit 2; }
archive_dir="$BACKUP_ROOT/seasons/$SERVER_SLUG/$SEASON_SLUG"
for path in "$BACKUP_ROOT" "$BACKUP_ROOT/seasons" "$BACKUP_ROOT/seasons/$SERVER_SLUG" "$archive_dir"; do
  [[ ! -L "$path" ]] || { echo 'season-end: unsafe archive path' >&2; exit 2; }
done
[[ ! -e "$archive_dir/world-final.tar.gz" && ! -L "$archive_dir/world-final.tar.gz" ]] || { echo 'season-end: permanent archive already exists; refusing overwrite' >&2; exit 2; }

# Always acquire the lifecycle lock ourselves. Never trust an inherited
# BACKUP_LOCK_HELD value; only the child backup receives it after this flock.
# Require an existing, non-symlink parent and create only the final state leaf.
[[ "$STATE_DIR" == /* && "$(basename -- "$STATE_DIR")" == '.reset-state' ]] || { echo 'season-end: STATE_DIR must be an absolute dedicated .reset-state directory' >&2; exit 2; }
state_parent="$(dirname -- "$STATE_DIR")"
[[ -d "$state_parent" ]] || { echo 'season-end: state parent must already exist' >&2; exit 2; }
state_parent_real="$(realpath -e -- "$state_parent")"
state_real="$(realpath -m -- "$STATE_DIR")"
[[ "$state_parent_real" == "$state_parent" && "$state_real" == "$state_parent_real/.reset-state" && ! -L "$state_parent" && ! -L "$STATE_DIR" ]] || { echo 'season-end: unsafe state path' >&2; exit 2; }
# Reject symlinked ancestors even when the final parent resolves successfully.
walk="$state_parent_real"
while [[ "$walk" != / ]]; do
  [[ ! -L "$walk" ]] || { echo 'season-end: symlinked state ancestor refused' >&2; exit 2; }
  walk="$(dirname -- "$walk")"
done
[[ ! -L "$STATE_DIR" ]] || { echo 'season-end: unsafe state directory' >&2; exit 2; }
mkdir -- "$STATE_DIR" 2>/dev/null || [[ -d "$STATE_DIR" && ! -L "$STATE_DIR" ]] || { echo 'season-end: cannot create safe state directory' >&2; exit 2; }
chmod 700 "$STATE_DIR"
lockfile="$STATE_DIR/lifecycle.lock"
[[ ! -L "$lockfile" ]] || { echo 'season-end: lifecycle lock must not be a symlink' >&2; exit 2; }
if [[ -e "$lockfile" ]]; then
  [[ -f "$lockfile" && "$(stat -c %h -- "$lockfile")" == 1 ]] || { echo 'season-end: unsafe lifecycle lock' >&2; exit 2; }
fi
exec 9>>"$lockfile"
[[ -f "$lockfile" && ! -L "$lockfile" && "$(stat -c %h -- "$lockfile")" == 1 ]] || { echo 'season-end: unsafe lifecycle lock' >&2; exit 2; }
chmod 600 "$lockfile"
flock -n 9 || { echo 'season-end: lifecycle busy; refusing to overlap reset, recovery, or backup' >&2; exit 2; }

echo "== season-end: $SERVER_SLUG/$SEASON_SLUG =="
echo "== step 1: final backup =="
daily_dir="$BACKUP_ROOT/daily"
[[ ! -L "$daily_dir" ]] || { echo 'season-end: unsafe daily archive directory' >&2; exit 2; }
before_backups=""
if [[ -d "$daily_dir" ]]; then
  before_backups="$(find "$daily_dir" -maxdepth 1 -type f -name 'world-*.tar.gz' -printf '%f\n' | sort)"
fi
env -u BACKUP_LOCK_HELD BACKUP_LOCK_HELD=1 SERVER_DIR="$SERVER_DIR" STATE_DIR="$STATE_DIR" BACKUP_ROOT="$BACKUP_ROOT" bash "$HERE/backup.sh"
[[ -d "$daily_dir" && ! -L "$daily_dir" ]] || { echo 'season-end: backup did not create a safe daily directory' >&2; exit 2; }
after_backups="$(find "$daily_dir" -maxdepth 1 -type f -name 'world-*.tar.gz' -printf '%f\n' | sort)"
mapfile -t new_backups < <(comm -13 <(printf '%s\n' "$before_backups" | sed '/^$/d') <(printf '%s\n' "$after_backups" | sed '/^$/d'))
[[ "${#new_backups[@]}" == 1 && "${new_backups[0]}" =~ ^world-[0-9]{8}-[0-9]{6}\.tar\.gz$ ]] || { echo 'season-end: could not identify exactly one newly produced backup' >&2; exit 2; }
latest="$daily_dir/${new_backups[0]}"

echo "== step 2: generate sanitized policy (review before Git) =="
SERVER_DIR="$SERVER_DIR" REPO_DIR="$REPO_DIR" SERVER_SLUG="$SERVER_SLUG" SEASON_SLUG="$SEASON_SLUG" \
  bash "$HERE/snapshot-to-git.sh"

echo "== step 3: archive world copy (on disk, not in git) =="
if [[ -f "$latest" && ! -L "$latest" ]]; then
  bash "$HERE/backup-verify.sh" "$latest"
  mkdir -p -- "$archive_dir"
  chmod 700 "$BACKUP_ROOT/seasons" "$BACKUP_ROOT/seasons/$SERVER_SLUG" "$archive_dir"
  temporary="$(mktemp "$archive_dir/.world-final.XXXXXX")"
  trap 'rm -f -- "$temporary"' EXIT
  cp -- "$latest" "$temporary"
  chmod 600 "$temporary"
  ln -- "$temporary" "$archive_dir/world-final.tar.gz" || { echo 'season-end: archive publication refused' >&2; exit 2; }
  rm -f -- "$temporary"
  trap - EXIT
  echo 'Permanent private archive created outside Git.'
else
  echo 'season-end: no final backup found; refusing to close season' >&2
  exit 2
fi

echo "== step 4: stamp README =="
python3 - "$SEASON_DIR/README.md" <<'PY'
import datetime, pathlib, sys
from zoneinfo import ZoneInfo
path = pathlib.Path(sys.argv[1])
lines = path.read_text().splitlines()
date = datetime.datetime.now(ZoneInfo('UTC')).date().isoformat()
if not any(line.startswith('| End date |') for line in lines):
    raise SystemExit('season-end: end-date field missing; archive retained')
path.write_text('\n'.join(f'| End date | {date} |' if line.startswith('| End date |') else line for line in lines) + '\n')
PY

cat <<EOF

Season closed. Remaining manual steps:
  - Note seed/players/events in $SEASON_DIR/README.md
  - Backups remain on owner-controlled local storage; no offsite copy is configured.
  - Review shared map waypoints for closed-season locations during live cutover; do not delete them automatically.
EOF
