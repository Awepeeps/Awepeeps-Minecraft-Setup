#!/usr/bin/env bash
# Publish a local private health summary; never sends a message or archive.
set -euo pipefail
umask 077
STATE_DIR="${STATE_DIR:-/srv/minecraft/.reset-state}"
[[ ! -L "$STATE_DIR" ]] || { echo 'maintenance report: unsafe state directory' >&2; exit 2; }
mkdir -p -- "$STATE_DIR"
temporary="$(mktemp "$STATE_DIR/.maintenance-report.XXXXXX")"
trap 'rm -f -- "$temporary"' EXIT
result=0
python3 "$(dirname -- "$0")/maintenance-status.py" >"$temporary" 2>/dev/null || result=$?
if (( result != 0 )) && [[ ! -s "$temporary" ]]; then
  printf 'ATTENTION: local maintenance report could not be generated; details suppressed.\n' >"$temporary"
fi
mv -fT -- "$temporary" "$STATE_DIR/maintenance-status.txt"
cat -- "$STATE_DIR/maintenance-status.txt"
exit "$result"
