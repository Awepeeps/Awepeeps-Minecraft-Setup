#!/usr/bin/env bash
# Toggle a persistent inhibit marker for any automatic boot-recovery job, so an
# operator can intentionally leave the server stopped without a recovery job
# reopening it.
set -euo pipefail
umask 077
action="${1:-}"
STATE_DIR="${STATE_DIR:-/srv/minecraft/.reset-state}"
LOCK_TIMEOUT="${LOCK_TIMEOUT:-1200}"
die() { printf 'recovery-gate: %s\n' "$*" >&2; exit 2; }
[[ "$action" == disable || "$action" == enable ]] || die 'usage: recovery-gate.sh disable|enable'
[[ ! -L "$STATE_DIR" ]] || die 'STATE_DIR must not be a symlink'
mkdir -p -- "$STATE_DIR"
[[ "$LOCK_TIMEOUT" =~ ^[0-9]+$ ]] || die 'LOCK_TIMEOUT must be a non-negative integer'
[[ ! -L "$STATE_DIR/lifecycle.lock" ]] || die 'lifecycle lock must not be a symlink'
lockfile="$STATE_DIR/lifecycle.lock"
[[ ! -e "$lockfile" || ( -f "$lockfile" && "$(stat -c %h -- "$lockfile")" == 1 ) ]] || die 'lifecycle lock must be a single-link regular file'
exec 9>>"$lockfile"
[[ -f "$lockfile" && ! -L "$lockfile" && "$(stat -c %h -- "$lockfile")" == 1 ]] || die 'lifecycle lock changed or is hard-linked'
flock -w "$LOCK_TIMEOUT" 9 || die 'lifecycle lock remained busy'
gate="$STATE_DIR/recovery.disabled"
[[ ! -L "$gate" ]] || die 'recovery gate must not be a symlink'
if [[ "$action" == disable ]]; then
  if [[ -e "$gate" ]]; then
    [[ -f "$gate" && "$(stat -c %h -- "$gate")" == 1 ]] || die 'recovery gate must be a single-link regular file'
  else
    tmp="$(mktemp "$STATE_DIR/.recovery.disabled.XXXXXX")"
    chmod 600 "$tmp"
    mv -- "$tmp" "$gate"
  fi
  printf 'boot recovery disabled; it will stay disabled until explicitly enabled\n'
else
  if [[ -e "$gate" ]]; then
    [[ -f "$gate" && "$(stat -c %h -- "$gate")" == 1 ]] || die 'recovery gate must be a single-link regular file'
    rm -- "$gate"
  fi
  printf 'boot recovery enabled\n'
fi
