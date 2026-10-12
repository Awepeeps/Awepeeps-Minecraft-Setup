#!/usr/bin/env bash
# Build the pinned Awepeeps Spawn Kit (test-only) from source and verify its
# artifact hash against the test-only manifest. Requires git, Docker, and the
# digest-pinned Gradle/JDK image used by the source repository.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
src_env="${SPAWN_KIT_SOURCE_ENV:-$ROOT/config/sources/spawn-kit.env}"
die() { echo "build-spawn-kit: $*" >&2; exit 2; }
[[ -f "$src_env" && ! -L "$src_env" ]] || die "missing $src_env; copy config/sources/spawn-kit.env.example and fill it in"
# shellcheck source=/dev/null
source "$src_env"
: "${SPAWN_KIT_SOURCE_REPOSITORY:?set SPAWN_KIT_SOURCE_REPOSITORY in $src_env}"
: "${SPAWN_KIT_SOURCE_COMMIT:?set SPAWN_KIT_SOURCE_COMMIT in $src_env}"
: "${SPAWN_KIT_VERSION:?set SPAWN_KIT_VERSION in $src_env}"
[[ "$SPAWN_KIT_SOURCE_REPOSITORY" == "https://github.com/Awepeeps/Awepeeps-SpawnKit.git" ]] || die 'SPAWN_KIT_SOURCE_REPOSITORY must be the Awepeeps-SpawnKit repository'
[[ "$SPAWN_KIT_SOURCE_COMMIT" =~ ^[0-9a-f]{40}$ ]] || die 'SPAWN_KIT_SOURCE_COMMIT must be a full 40-character commit'
[[ "$SPAWN_KIT_VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || die 'SPAWN_KIT_VERSION must look like x.y.z'

manifest="${PLUGIN_MANIFEST:-$ROOT/plugins/test-plugins.list}"
[[ -f "$manifest" ]] || die "test-only manifest not found: $manifest"

BUILD_DIR="$(mktemp -d "${TMPDIR:-/tmp}/awepeeps-spawn-kit-build.XXXXXX")"
GRADLE_CACHE="$BUILD_DIR/gradle-cache"
mkdir -p "$GRADLE_CACHE"
trap 'rm -rf -- "$BUILD_DIR"' EXIT

git clone --quiet --no-checkout "$SPAWN_KIT_SOURCE_REPOSITORY" "$BUILD_DIR/source"
git -C "$BUILD_DIR/source" checkout --quiet --detach "$SPAWN_KIT_SOURCE_COMMIT"
[[ "$(git -C "$BUILD_DIR/source" rev-parse HEAD)" == "$SPAWN_KIT_SOURCE_COMMIT" ]] || die 'checked-out commit does not match the pin'
SOURCE_DIR="$BUILD_DIR/source"
[[ -f "$SOURCE_DIR/build.gradle" && ! -L "$SOURCE_DIR/build.gradle" ]] || die 'source repository does not look like the expected Gradle project'

docker run --rm --platform linux/amd64 \
  --user "$(id -u):$(id -g)" \
  --volume "$SOURCE_DIR:/workspace:ro" \
  --volume "$BUILD_DIR:/build" \
  --volume "$GRADLE_CACHE:/gradle-cache" \
  --env GRADLE_USER_HOME=/gradle-cache \
  --workdir /workspace \
  gradle:9.1.0-jdk25@sha256:0a0fe3f8fb6e4ddd7ecf3f4d53b6f3f758add80e868bb95d72e3bbff420c1f68 \
  bash -euc '
    mkdir -p /build/module
    tar -C /workspace --exclude=.git --exclude=.gradle --exclude=build -cf - . |
      tar -C /build/module -xf -
    find /build/module -type d -exec chmod 0755 {} +
    find /build/module -type f -exec chmod 0644 {} +
    cd /build/module
    bash ./gradlew --no-daemon clean test build
    install -D -m 0644 "build/libs/awepeeps-spawn-kit-'"$SPAWN_KIT_VERSION"'.jar" \
      "/build/awepeeps-spawn-kit-'"$SPAWN_KIT_VERSION"'.jar"
  '

JAR="$BUILD_DIR/awepeeps-spawn-kit-$SPAWN_KIT_VERSION.jar"
EXPECTED="$(awk -F'|' '$1=="AwepeepsSpawnKit"{print $5}' "$manifest")"
[[ "$EXPECTED" =~ ^[0-9a-f]{64}$ ]] || die 'AwepeepsSpawnKit manifest entry must carry a real 64-character SHA-256'
[[ -f "$JAR" ]] || die 'build did not produce the expected jar'
ACTUAL="$(sha256sum "$JAR" | cut -d' ' -f1)"
[[ "$ACTUAL" == "$EXPECTED" ]] || die 'Awepeeps Spawn Kit artifact hash differs from the pinned test-only manifest entry'
mkdir -p "$ROOT/artifacts"
cp -- "$JAR" "$ROOT/artifacts/AwepeepsSpawnKit-$SPAWN_KIT_VERSION.jar"
printf 'Verified %s\n' "$ROOT/artifacts/AwepeepsSpawnKit-$SPAWN_KIT_VERSION.jar"
