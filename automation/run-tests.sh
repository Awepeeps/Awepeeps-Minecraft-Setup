#!/usr/bin/env bash
# Run every portable mock test suite. No Docker daemon, network, or live server
# is contacted. Suitable for CI.
set -euo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
status=0
# Keep Python from leaving __pycache__ directories behind.
export PYTHONDONTWRITEBYTECODE=1

run() {
  printf '\n== %s ==\n' "$*"
  if ! "$@"; then status=1; fi
}

run bash "$HERE/test-backup.sh"
run bash "$HERE/test-install-plugins.sh"
run bash "$HERE/test-daily-reset.sh"
run python3 "$HERE/test-maintenance-status.py"
run python3 "$HERE/test-snapshot-policy.py"
run python3 "$HERE/test-season-end.py"

if (( status != 0 )); then
  printf '\nOne or more test suites failed.\n' >&2
  exit 1
fi
printf '\nAll portable mock test suites passed.\n'
