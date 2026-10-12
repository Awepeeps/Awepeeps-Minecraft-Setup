#!/usr/bin/env bash
# Isolated mocks for install-plugins.sh. Serves jars over localhost only and
# never touches the network.
set -euo pipefail
root="$(cd -- "$(dirname -- "$0")/.." && pwd)"
tmp="$(mktemp -d)"
trap 'rm -rf -- "$tmp"; [[ -n "${server_pid:-}" ]] && kill "$server_pid" 2>/dev/null || true' EXIT

mkdir -p "$tmp/serve" "$tmp/server"
# A minimal valid .jar signature so the PK zip check passes.
printf 'PK\003\004fixture-jar-bytes\n' > "$tmp/serve/Good-1.0.0.jar"
good_sha="$(sha256sum "$tmp/serve/Good-1.0.0.jar" | cut -d' ' -f1)"
printf 'PK\003\004other\n' > "$tmp/serve/Bad-1.0.0.jar"
bad_sha="$(sha256sum "$tmp/serve/Bad-1.0.0.jar" | cut -d' ' -f1)"

port="$(python3 -c 'import socket; s=socket.socket(); s.bind(("",0)); print(s.getsockname()[1]); s.close()')"
python3 -m http.server "$port" --bind localhost --directory "$tmp/serve" >/dev/null 2>&1 &
server_pid=$!
for _ in $(seq 1 50); do curl -fsS "http://localhost:$port/Good-1.0.0.jar" -o /dev/null 2>/dev/null && break; sleep 0.1; done

cat > "$tmp/good.list" <<EOF
# fixture manifest
Good|fixture|1.0.0|http://localhost:$port/Good-1.0.0.jar|$good_sha
EOF
cat > "$tmp/mismatch.list" <<EOF
Good|fixture|1.0.0|http://localhost:$port/Good-1.0.0.jar|$bad_sha
EOF
cat > "$tmp/placeholder.list" <<EOF
ViaVersion|GitHub Releases|5.12.1|TODO_RELEASE_JAR_URL|TODO_64_HEX_SHA256
EOF
cat > "$tmp/nonhttps.list" <<EOF
Good|fixture|1.0.0|http://example.invalid/Good-1.0.0.jar|$good_sha
EOF
cat > "$tmp/notajar.list" <<EOF
Compass|source commit abc|1.0.0|https://github.com/Awepeeps/Awepeeps-BlueMap-Compass/tree/abc|$good_sha
EOF

failures=0
check() { local name="$1"; shift; if "$@"; then echo "ok - $name"; else echo "not ok - $name"; failures=$((failures + 1)); fi; }

install() { PLUGIN_MANIFEST="$1" SERVER_DIR="$tmp/server" bash "$root/automation/install-plugins.sh" >"$tmp/out" 2>&1; }
export -f install
export root tmp port good_sha bad_sha

check good_jar_installed_and_verified bash -c 'install "$tmp/good.list" && [[ -f "$tmp/server/plugins/Good.jar" ]] && grep -q "installed" "$tmp/out"'
check dry_run_does_not_copy bash -c 'rm -rf "$tmp/server/plugins"; PLUGIN_MANIFEST="$tmp/good.list" DRY_RUN=1 SERVER_DIR="$tmp/server" bash "$root/automation/install-plugins.sh" >/dev/null && [[ ! -f "$tmp/server/plugins/Good.jar" ]]'
check hash_mismatch_fails bash -c '! install "$tmp/mismatch.list" && grep -q "mismatch" "$tmp/out"'
check placeholder_skipped bash -c 'install "$tmp/placeholder.list" && grep -q "skip ViaVersion" "$tmp/out"'
check strict_promotes_skip_to_failure bash -c '! PLUGIN_MANIFEST="$tmp/placeholder.list" STRICT=1 SERVER_DIR="$tmp/server" bash "$root/automation/install-plugins.sh" >/dev/null 2>&1'
check non_https_rejected bash -c 'install "$tmp/nonhttps.list" && grep -q "not https" "$tmp/out"'
check non_jar_source_skipped bash -c 'install "$tmp/notajar.list" && grep -q "skip Compass" "$tmp/out"'
check traversal_name_rejected bash -c 'printf "Bad/Name|x|1.0.0|https://example.invalid/x.jar|%s\n" "$good_sha" > "$tmp/bad-name.list"; ! install "$tmp/bad-name.list"'

if (( failures )); then printf '%d install-plugins test(s) failed\n' "$failures" >&2; exit 1; fi
printf 'all install-plugins mock tests passed\n'
