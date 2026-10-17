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

# Read-only whitelist enforcement check when the instance directory is known.
# Safe on a running server: it only reads server.properties and makes no change.
if [[ -n "${SERVER_DIR:-}" ]]; then
  printf '\n' >>"$temporary"
  whitelist_result=0
  SERVER_DIR="$SERVER_DIR" bash "$(dirname -- "$0")/whitelist-check.sh" >>"$temporary" 2>&1 || whitelist_result=$?
  if (( whitelist_result != 0 )); then
    printf 'ATTENTION: the whitelist is not enforced on the running server.\n' >>"$temporary"
    result=1
  fi
else
  printf '\nwhitelist check: skipped (SERVER_DIR is not set for the maintenance report service).\n' >>"$temporary"
fi

mv -fT -- "$temporary" "$STATE_DIR/maintenance-status.txt"
cat -- "$STATE_DIR/maintenance-status.txt"
exit "$result"
