#!/usr/bin/env bash
# Verify the whitelist is actually enforced. Read-only; never edits anything.
#
# The itzg/minecraft-server image can rewrite server.properties from its
# environment at startup, so a fresh instance, a daily reset and a container
# recreate can all silently turn the whitelist off. This check reads the mounted
# server.properties and fails loudly when either whitelist property is not true.
#
# Environment:
#   SERVER_DIR           the instance data directory (required)
#   ONLINE_MODE_REQUIRED 1 = also fail when online-mode is not true (default 0)
#
# Exits 0 when enforced, 1 when a required property is not true, 2 on bad input.
set -euo pipefail
SERVER_DIR="${SERVER_DIR:-}"
ONLINE_MODE_REQUIRED="${ONLINE_MODE_REQUIRED:-0}"

[[ -n "$SERVER_DIR" && "$SERVER_DIR" != / && ! -L "$SERVER_DIR" && -d "$SERVER_DIR" ]] \
  || { echo 'whitelist check: SERVER_DIR must be an existing real instance directory' >&2; exit 2; }
server_dir="$(realpath -e -- "$SERVER_DIR")"
case "$server_dir" in
  /|/home|/root|/srv|/mnt|/opt|/usr|/var|/etc)
    echo 'whitelist check: SERVER_DIR resolves to a protected parent directory' >&2
    exit 2;;
esac
props="$server_dir/server.properties"
if [[ ! -f "$props" || -L "$props" ]]; then
  echo 'whitelist check: server.properties must be a regular, non-symlink file' >&2
  exit 2
fi

# Take the last occurrence of a key; Java properties loading lets a later entry
# win, so a stale earlier value must not hide a later one.
value_for() {
  awk -v key="$1" '
    index($0, key "=") == 1 {
      v = substr($0, length(key) + 2)
      sub(/\r$/, "", v)
      gsub(/^[ \t]+|[ \t]+$/, "", v)
    }
    END { if (v != "") print v }
  ' "$props"
}

failures=0
echo "whitelist check (server: $props)"
for key in white-list enforce-whitelist; do
  value="$(value_for "$key")"
  lowered="${value,,}"
  if [[ "$lowered" == 'true' ]]; then
    printf '  %s=%s (ok)\n' "$key" "$value"
  elif [[ -z "$value" ]]; then
    printf '  %s is missing (FAIL: expected true)\n' "$key"
    failures=$((failures + 1))
  else
    printf '  %s=%s (FAIL: expected true)\n' "$key" "$value"
    failures=$((failures + 1))
  fi
done
online_mode="$(value_for online-mode)"
if [[ -n "$online_mode" ]]; then
  printf '  online-mode=%s (info)\n' "$online_mode"
  if [[ "$ONLINE_MODE_REQUIRED" == 1 && "${online_mode,,}" != 'true' ]]; then
    printf '  online-mode is required to be true (FAIL)\n'
    failures=$((failures + 1))
  fi
fi

if (( failures > 0 )); then
  printf 'result: FAILED (%d required whitelist property/properties not enabled)\n' "$failures"
  echo 'whitelist check: the server is NOT fail-closed; enable white-list and enforce-whitelist' >&2
  exit 1
fi
printf 'result: OK (whitelist is enforced)\n'
