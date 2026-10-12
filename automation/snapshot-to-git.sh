#!/usr/bin/env bash
# Generate a sanitized, reviewable policy JSON file. Publishing is a separate
# human-reviewed operation; this script never stages, commits, or pushes.
set -euo pipefail

HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
REPO_DIR="${REPO_DIR:-$(cd -- "$HERE/.." && pwd -P)}"
SERVER_DIR="${SERVER_DIR:-}"
SERVER_SLUG="${SERVER_SLUG:-survival}"
SEASON_SLUG="${SEASON_SLUG:-season-1}"

[[ -n "$SERVER_DIR" ]] || { echo "SERVER_DIR must be set (instance data dir)" >&2; exit 2; }
python3 "$HERE/snapshot-policy.py" \
  --repo-dir "$REPO_DIR" \
  --server-dir "$SERVER_DIR" \
  --server-slug "$SERVER_SLUG" \
  --season-slug "$SEASON_SLUG"
