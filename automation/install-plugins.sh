#!/usr/bin/env bash
# Install pinned plugin jars into a server's plugins/ directory.
#
# Reads a manifest in the same pipe-separated format used by the deployment:
#   name|source|version|url|sha256
# Blank lines and lines beginning with '#' are ignored. Lines whose url does not
# end in .jar (custom plugins built from source) and lines that still contain a
# placeholder are skipped unless STRICT=1. Every downloaded jar is verified
# against its SHA-256 before it is copied into place.
#
# Environment (see .env.example):
#   SERVER_DIR        required: instance data directory (contains plugins/)
#   PLUGIN_MANIFEST   default: <repo>/plugins/plugins.list
#   ARTIFACTS_DIR     default: <repo>/artifacts (unused here; custom plugins live there)
#   DRY_RUN           1 to download/verify without copying
#   STRICT            1 to fail when a manifest line is skipped
#   PLUGINS_DIR_NAME  default: plugins
set -euo pipefail
umask 022

HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
REPO_DIR="$(cd -- "$HERE/.." && pwd -P)"
SERVER_DIR="${SERVER_DIR:-}"
PLUGIN_MANIFEST="${PLUGIN_MANIFEST:-$REPO_DIR/plugins/plugins.list}"
PLUGINS_DIR_NAME="${PLUGINS_DIR_NAME:-plugins}"
DRY_RUN="${DRY_RUN:-0}"
STRICT="${STRICT:-0}"

die() { echo "install-plugins: $*" >&2; exit 2; }
log() { printf 'install-plugins: %s\n' "$*"; }

[[ -n "$SERVER_DIR" && "$SERVER_DIR" != / && ! -L "$SERVER_DIR" && -d "$SERVER_DIR" ]] || die 'SERVER_DIR must be an existing real instance directory'
server_dir="$(realpath -e -- "$SERVER_DIR")"
[[ -f "$PLUGIN_MANIFEST" && ! -L "$PLUGIN_MANIFEST" ]] || die "manifest not found: $PLUGIN_MANIFEST"
[[ "$PLUGINS_DIR_NAME" =~ ^[A-Za-z0-9._-]+$ ]] || die 'PLUGINS_DIR_NAME must be a simple directory name'
plugins_dir="$server_dir/$PLUGINS_DIR_NAME"
[[ ! -L "$plugins_dir" ]] || die "$PLUGINS_DIR_NAME must not be a symlink"
mkdir -p -- "$plugins_dir"
[[ -d "$plugins_dir" && "$(realpath -e -- "$plugins_dir")" == "$plugins_dir" ]] || die "$PLUGINS_DIR_NAME must resolve inside SERVER_DIR"

command -v sha256sum >/dev/null || die 'sha256sum is required'
if command -v curl >/dev/null; then
  fetch() { curl -fsSL --retry 3 -o "$1" "$2"; }
elif command -v wget >/dev/null; then
  fetch() { wget -q -O "$1" "$2"; }
else
  die 'curl or wget is required'
fi

tmp="$(mktemp -d "${TMPDIR:-/tmp}/install-plugins.XXXXXX")"
trap 'rm -rf -- "$tmp"' EXIT

installed=0 skipped=0
# Read fields explicitly; never eval manifest content.
while IFS='|' read -r name source version url sha; do
  [[ -z "${name// }" ]] && continue
  case "$name" in \#*) continue ;; esac
  [[ "$name" =~ ^[A-Za-z0-9._-]+$ ]] || die "unsafe plugin name in manifest: $name"
  version="${version//[[:space:]]/}"
  url="${url//[[:space:]]/}"
  sha="${sha//[[:space:]]/}"
  if [[ "$sha" =~ ^[0-9a-f]{64}$ && "$url" == *.jar ]]; then
    :
  else
    log "skip $name ($version): source=$source — pin the artifact URL and its SHA-256, or build it locally with the matching automation/build-*.sh"
    skipped=$((skipped + 1))
    continue
  fi
  if [[ "$url" != https://* && "$url" != http://localhost* ]]; then
    log "skip $name: refusing artifact URL that is not https (or localhost for tests)"
    skipped=$((skipped + 1))
    continue
  fi
  dest="$tmp/$name.jar"
  log "downloading $name ($version)"
  fetch "$dest" "$url" || die "download failed for $name"
  actual="$(sha256sum "$dest" | cut -d' ' -f1)"
  [[ "$actual" == "$sha" ]] || die "SHA-256 mismatch for $name (expected $sha, got $actual)"
  head -c 2 "$dest" | grep -q 'PK' || die "$name is not a Java archive (no PK zip signature)"
  if [[ "$DRY_RUN" == 1 ]]; then
    log "verified $name (dry run; not copied)"
  else
    cp -- "$dest" "$plugins_dir/$name.jar"
    log "installed $plugins_dir/$name.jar ($version)"
  fi
  installed=$((installed + 1))
done < "$PLUGIN_MANIFEST"

log "done: $installed installed, $skipped skipped"
if [[ "$skipped" -gt 0 && "$STRICT" == 1 ]]; then
  die "STRICT=1 and $skipped manifest entries were skipped"
fi
