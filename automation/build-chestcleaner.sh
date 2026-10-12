#!/usr/bin/env bash
# Build the pinned Awepeeps ChestCleaner fork from source and verify its
# artifact hash against the manifest. Requires git and the toolchain the source
# repository documents (Java + Gradle wrapper).
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
src_env="${CHESTCLEANER_SOURCE_ENV:-$ROOT/config/sources/chestcleaner.env}"
die() { echo "build-chestcleaner: $*" >&2; exit 2; }
[[ -f "$src_env" && ! -L "$src_env" ]] || die "missing $src_env; copy config/sources/chestcleaner.env.example and fill it in"
# shellcheck source=/dev/null
source "$src_env"
: "${CHESTCLEANER_SOURCE_REPOSITORY:?set CHESTCLEANER_SOURCE_REPOSITORY in $src_env}"
: "${CHESTCLEANER_SOURCE_COMMIT:?set CHESTCLEANER_SOURCE_COMMIT in $src_env}"
: "${CHESTCLEANER_VERSION:?set CHESTCLEANER_VERSION in $src_env}"
# Plugin source and its toolchain live in the independent maintained repository.
[[ "$CHESTCLEANER_SOURCE_REPOSITORY" == "https://github.com/Awepeeps/Awepeeps-ChestCleaner.git" ]] || die 'CHESTCLEANER_SOURCE_REPOSITORY must be the Awepeeps-ChestCleaner repository'
[[ "$CHESTCLEANER_SOURCE_COMMIT" =~ ^[0-9a-f]{40}$ ]] || die 'CHESTCLEANER_SOURCE_COMMIT must be a full 40-character commit'
[[ "$CHESTCLEANER_VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+-awepeeps\.[0-9]+$ ]] || die 'CHESTCLEANER_VERSION must look like x.y.z-awepeeps.n'

manifest="${PLUGIN_MANIFEST:-$ROOT/plugins/plugins.list}"
[[ -f "$manifest" ]] || die "manifest not found: $manifest"

BUILD_DIR="$(mktemp -d "${TMPDIR:-/tmp}/awepeeps-chestcleaner-build.XXXXXX")"
trap 'rm -rf -- "$BUILD_DIR"' EXIT
git clone --quiet --no-checkout "$CHESTCLEANER_SOURCE_REPOSITORY" "$BUILD_DIR/source"
git -C "$BUILD_DIR/source" checkout --quiet --detach "$CHESTCLEANER_SOURCE_COMMIT"
[[ "$(git -C "$BUILD_DIR/source" rev-parse HEAD)" == "$CHESTCLEANER_SOURCE_COMMIT" ]] || die 'checked-out commit does not match the pin'
bash "$BUILD_DIR/source/automation/build-chestcleaner.sh"
JAR="$BUILD_DIR/source/target/chestcleaner-$CHESTCLEANER_VERSION.jar"
EXPECTED="$(awk -F'|' '$1=="ChestCleaner"{print $5}' "$manifest")"
[[ "$EXPECTED" =~ ^[0-9a-f]{64}$ ]] || die 'ChestCleaner manifest entry must carry a real 64-character SHA-256'
[[ -f "$JAR" ]] || die 'build did not produce the expected jar'
[[ "$(sha256sum "$JAR" | cut -d' ' -f1)" == "$EXPECTED" ]] || die 'ChestCleaner artifact hash differs from the pinned manifest entry'
mkdir -p "$ROOT/artifacts"
cp -- "$JAR" "$ROOT/artifacts/ChestCleaner-$CHESTCLEANER_VERSION.jar"

printf 'Verified %s\n' "$ROOT/artifacts/ChestCleaner-$CHESTCLEANER_VERSION.jar"
