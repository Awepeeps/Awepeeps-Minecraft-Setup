#!/usr/bin/env bash
# Isolated tests for whitelist-check.sh. No Docker, no network, no server.
set -euo pipefail
root="$(cd -- "$(dirname -- "$0")/.." && pwd)"
tmp="$(mktemp -d)"
trap 'rm -rf -- "$tmp"' EXIT
mkdir -p "$tmp/server"
export SERVER_DIR="$tmp/server" tmp root

write_props() { printf '%b' "$1" > "$SERVER_DIR/server.properties"; }
run_wl() {
  local rc=0
  SERVER_DIR="$SERVER_DIR" ONLINE_MODE_REQUIRED="${ONLINE_MODE_REQUIRED:-0}" \
    bash "$root/automation/whitelist-check.sh" >"$tmp/out" 2>&1 || rc=$?
  printf '%s' "$rc" > "$tmp/rc"
}
rc_is() { [[ "$(cat "$tmp/rc")" == "$1" ]]; }
out_has() { grep -Fq -- "$1" "$tmp/out"; }
export -f write_props run_wl rc_is out_has

failures=0
check() { local name="$1"; shift; if "$@"; then printf 'ok - %s\n' "$name"; else printf 'not ok - %s\n' "$name"; sed 's/^/    /' "$tmp/out" 2>/dev/null || true; failures=$((failures+1)); fi; }

check both_properties_true bash -c 'set -e
write_props "level-name=world\nwhite-list=true\nenforce-whitelist=true\nonline-mode=true\n"
run_wl
rc_is 0
out_has "result: OK"'

check white_list_false_fails bash -c 'set -e
write_props "white-list=false\nenforce-whitelist=true\n"
run_wl
rc_is 1
out_has "white-list=false (FAIL"'

check enforce_whitelist_false_fails bash -c 'set -e
write_props "white-list=true\nenforce-whitelist=false\n"
run_wl
rc_is 1
out_has "enforce-whitelist=false (FAIL"'

check missing_property_fails bash -c 'set -e
write_props "white-list=true\n"
run_wl
rc_is 1
out_has "enforce-whitelist is missing (FAIL"'

check empty_value_fails bash -c 'set -e
write_props "white-list=\nenforce-whitelist=true\n"
run_wl
rc_is 1
out_has "white-list is missing (FAIL"'

check case_insensitive_true_passes bash -c 'set -e
write_props "white-list=TRUE\nenforce-whitelist=True\n"
run_wl
rc_is 0'

check last_occurrence_wins_false bash -c 'set -e
write_props "white-list=true\nwhite-list=false\nenforce-whitelist=true\n"
run_wl
rc_is 1'

check last_occurrence_wins_true bash -c 'set -e
write_props "white-list=false\nwhite-list=true\nenforce-whitelist=true\n"
run_wl
rc_is 0'

check crlf_values_pass bash -c 'set -e
write_props "white-list=true\r\nenforce-whitelist=true\r\n"
run_wl
rc_is 0'

check online_mode_false_is_informational bash -c 'set -e
write_props "white-list=true\nenforce-whitelist=true\nonline-mode=false\n"
run_wl
rc_is 0
out_has "online-mode=false (info)"'

check online_mode_required_can_fail bash -c 'set -e
write_props "white-list=true\nenforce-whitelist=true\nonline-mode=false\n"
ONLINE_MODE_REQUIRED=1 run_wl
rc_is 1'

check symlinked_properties_refused bash -c 'set -e
write_props "white-list=true\nenforce-whitelist=true\n"
mv "$SERVER_DIR/server.properties" "$tmp/real.properties"
ln -s "$tmp/real.properties" "$SERVER_DIR/server.properties"
run_wl
rc_is 2
rm -f "$SERVER_DIR/server.properties"'

check missing_server_dir_refused bash -c 'set -e
SERVER_DIR="$tmp/does-not-exist" run_wl
rc_is 2'

check protected_server_dir_refused bash -c 'set -e
SERVER_DIR=/ run_wl
rc_is 2'

if (( failures )); then printf '%d whitelist-check test(s) failed\n' "$failures" >&2; exit 1; fi
printf 'all whitelist-check tests passed\n'
