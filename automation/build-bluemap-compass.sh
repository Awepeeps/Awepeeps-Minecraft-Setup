#!/usr/bin/env bash
# Build the pinned Awepeeps BlueMap Compass fork from source and verify its
# artifact hash against the manifest. Requires git, Docker, and the toolchain the
# source repository documents.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
src_env="${BLUEMAP_COMPASS_SOURCE_ENV:-$ROOT/config/sources/bluemap-compass.env}"
die() { echo "build-bluemap-compass: $*" >&2; exit 2; }
[[ -f "$src_env" && ! -L "$src_env" ]] || die "missing $src_env; copy config/sources/bluemap-compass.env.example and fill it in"
# shellcheck source=/dev/null
source "$src_env"
: "${BLUEMAP_COMPASS_SOURCE_REPOSITORY:?set BLUEMAP_COMPASS_SOURCE_REPOSITORY in $src_env}"
: "${BLUEMAP_COMPASS_SOURCE_COMMIT:?set BLUEMAP_COMPASS_SOURCE_COMMIT in $src_env}"
: "${BLUEMAP_COMPASS_VERSION:?set BLUEMAP_COMPASS_VERSION in $src_env}"
[[ "$BLUEMAP_COMPASS_SOURCE_REPOSITORY" == "https://github.com/Awepeeps/Awepeeps-BlueMap-Compass.git" ]] || die 'BLUEMAP_COMPASS_SOURCE_REPOSITORY must be the Awepeeps-BlueMap-Compass repository'
[[ "$BLUEMAP_COMPASS_SOURCE_COMMIT" =~ ^[0-9a-f]{40}$ ]] || die 'BLUEMAP_COMPASS_SOURCE_COMMIT must be a full 40-character commit'
[[ "$BLUEMAP_COMPASS_VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+-awepeeps\.[0-9]+$ ]] || die 'BLUEMAP_COMPASS_VERSION must look like x.y.z-awepeeps.n'

manifest="${PLUGIN_MANIFEST:-$ROOT/plugins/plugins.list}"
[[ -f "$manifest" ]] || die "manifest not found: $manifest"

BUILD_DIR="$(mktemp -d "${TMPDIR:-/tmp}/awepeeps-bluemap-compass-build.XXXXXX")"
trap 'rm -rf -- "$BUILD_DIR"' EXIT
git clone --quiet --no-checkout "$BLUEMAP_COMPASS_SOURCE_REPOSITORY" "$BUILD_DIR/source"
git -C "$BUILD_DIR/source" checkout --quiet --detach "$BLUEMAP_COMPASS_SOURCE_COMMIT"
[[ "$(git -C "$BUILD_DIR/source" rev-parse HEAD)" == "$BLUEMAP_COMPASS_SOURCE_COMMIT" ]] || die 'checked-out commit does not match the pin'
bash "$BUILD_DIR/source/automation/build-bluemap-compass.sh"
JAR="$BUILD_DIR/source/build/libs/awepeeps-bluemap-compass-$BLUEMAP_COMPASS_VERSION.jar"
EXPECTED="$(awk -F'|' '$1=="AwepeepsBlueMapCompass"{print $5}' "$manifest")"
[[ "$EXPECTED" =~ ^[0-9a-f]{64}$ ]] || die 'AwepeepsBlueMapCompass manifest entry must carry a real 64-character SHA-256'
[[ -f "$JAR" ]] || die 'build did not produce the expected jar'
[[ "$(sha256sum "$JAR" | cut -d' ' -f1)" == "$EXPECTED" ]] || die 'BlueMap Compass artifact hash differs from the pinned manifest entry'
mkdir -p "$ROOT/artifacts"
cp -- "$JAR" "$ROOT/artifacts/AwepeepsBlueMapCompass-$BLUEMAP_COMPASS_VERSION.jar"
printf 'Verified %s\n' "$ROOT/artifacts/AwepeepsBlueMapCompass-$BLUEMAP_COMPASS_VERSION.jar"
