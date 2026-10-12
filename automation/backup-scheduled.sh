#!/usr/bin/env bash
# Scheduled phase gate for backups. Runs backup.sh only during the active
# phase and does not touch Docker or backup storage while the phase is inactive.
#
# BACKUP_PHASE=test -> runs before RESET_UNTIL (the disposable-test window).
# BACKUP_PHASE=live -> runs on/after RESET_UNTIL (the live season).
set -euo pipefail
RESET_UNTIL="${RESET_UNTIL:-2030-01-01}"
BACKUP_PHASE="${BACKUP_PHASE:-}"
BACKUP_TIMEZONE="${BACKUP_TIMEZONE:-UTC}"
[[ "$RESET_UNTIL" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]] || { echo 'Invalid RESET_UNTIL' >&2; exit 2; }
[[ "$BACKUP_PHASE" == test || "$BACKUP_PHASE" == live ]] || { echo 'BACKUP_PHASE must be test or live' >&2; exit 2; }
today="$(TZ="$BACKUP_TIMEZONE" date +%F)"
if { [[ "$BACKUP_PHASE" == test ]] && [[ ! "$today" < "$RESET_UNTIL" ]]; } ||
   { [[ "$BACKUP_PHASE" == live ]] && [[ "$today" < "$RESET_UNTIL" ]]; }; then
  printf 'Backup phase %s inactive on %s; no-op\n' "$BACKUP_PHASE" "$today"
  exit 0
fi
exec bash "$(dirname -- "$0")/backup.sh"
