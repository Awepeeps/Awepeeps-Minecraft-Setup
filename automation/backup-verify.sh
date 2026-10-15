#!/usr/bin/env bash
# Offline integrity, path-safety, and extraction verification for a backup
# archive. Never contacts a live server or the Docker daemon.
#
# Usage: backup-verify.sh [archive.tar.gz]
# With no argument the newest archive under "$BACKUP_ROOT/daily" is used.
set -euo pipefail
umask 077
BACKUP_ROOT="${BACKUP_ROOT:-/srv/minecraft/backups}"
PLUGIN_DATA_DIRS="${PLUGIN_DATA_DIRS:-plugins/AwepeepsBlueMapCompass plugins/AwepeepsSpawnKit}"
PLUGIN_DATA_PATHS="${PLUGIN_DATA_PATHS:-plugins/Essentials/config.yml plugins/Essentials/userdata}"
archive="${1:-}"
if [[ -z "$archive" ]]; then
  [[ ! -L "$BACKUP_ROOT/daily" ]] || { echo 'daily directory is a symlink' >&2; exit 2; }
  archive="$(find "$BACKUP_ROOT/daily" -maxdepth 1 -type f -regextype posix-extended -regex '.*/world-[0-9]{8}-[0-9]{6}\.tar\.gz' -printf '%f\n' | sort -r | head -n1)"
  [[ -n "$archive" ]] && archive="$BACKUP_ROOT/daily/$archive"
fi
[[ -f "$archive" && ! -L "$archive" ]] || { echo 'archive must be a regular, non-symlink file' >&2; exit 2; }
PLUGIN_DATA_DIRS="$PLUGIN_DATA_DIRS" PLUGIN_DATA_PATHS="$PLUGIN_DATA_PATHS" python3 - "$archive" <<'PY'
import os, pathlib, sys, tarfile, tempfile
archive = pathlib.Path(sys.argv[1])
allowed = {"world", "world_nether", "world_the_end", "server.properties", "backup-metadata.txt"}
plugin_dirs = set()
for rel in os.environ.get("PLUGIN_DATA_DIRS", "").split():
    plugin_dirs.add(pathlib.PurePosixPath(rel).as_posix())
plugin_paths = set(plugin_dirs)
for rel in os.environ.get("PLUGIN_DATA_PATHS", "").split():
    path = pathlib.PurePosixPath(rel)
    if path.is_absolute() or ".." in path.parts or not path.parts or path.parts[0] != "plugins":
        raise SystemExit(f"unsafe plugin data path in verifier configuration: {rel!r}")
    plugin_paths.add(path.as_posix())
allowed.update(plugin_dirs)
with tarfile.open(archive, "r:gz") as tf:
    members = tf.getmembers()
    if not members:
        raise SystemExit("empty archive")
    roots = set()
    for m in members:
        p = pathlib.PurePosixPath(m.name)
        if p.is_absolute() or ".." in p.parts or not p.parts:
            raise SystemExit(f"unsafe archive path: {m.name!r}")
        root = p.parts[0]
        if root not in allowed and not (root.startswith("paper-") and root.endswith(".jar") and len(p.parts) == 1):
            if root != "plugins":
                raise SystemExit(f"unexpected archive path: {m.name!r}")
        if root == "plugins":
            entry = p.as_posix()
            permitted = any(entry == path or entry.startswith(path + "/") or (m.isdir() and path.startswith(entry + "/")) for path in plugin_paths)
            if not permitted:
                raise SystemExit(f"unexpected plugin archive path: {m.name!r}")
        if not (m.isfile() or m.isdir()):
            raise SystemExit(f"links and special files are forbidden: {m.name!r}")
        roots.add(root if root != "plugins" else "/".join(p.parts[:2]))
    if not {"world", "server.properties"}.issubset(roots):
        raise SystemExit("required world or server.properties data missing")
    names = {pathlib.PurePosixPath(m.name).as_posix(): m for m in members if m.isfile()}
    level = names.get("world/level.dat")
    if level is None or level.size <= 0:
        raise SystemExit("world/level.dat is missing or empty")
    modern = "world/dimensions/minecraft/overworld" in {"/".join(pathlib.PurePosixPath(m.name).parts[:4]) for m in members}
    if modern:
        for dimension in ("overworld", "the_nether", "the_end"):
            prefix = f"world/dimensions/minecraft/{dimension}/region/"
            if not any(name.startswith(prefix) and name.endswith(".mca") and item.size > 0 for name, item in names.items()):
                raise SystemExit(f"missing non-empty region data for {dimension}")
    else:
        for root in ("world", "world_nether", "world_the_end"):
            if not any(name.startswith(root + "/region/") and name.endswith(".mca") and item.size > 0 for name, item in names.items()):
                raise SystemExit(f"missing non-empty legacy region data for {root}")
    with tempfile.TemporaryDirectory(prefix="mc-restore-verify-") as d:
        for m in members:
            target = pathlib.Path(d, *pathlib.PurePosixPath(m.name).parts)
            if m.isdir():
                target.mkdir(parents=True, exist_ok=True)
            else:
                target.parent.mkdir(parents=True, exist_ok=True)
                src = tf.extractfile(m)
                if src is None:
                    raise SystemExit(f"cannot read member: {m.name}")
                with src, target.open("xb") as out:
                    while chunk := src.read(1024 * 1024):
                        out.write(chunk)
print(f"integrity and safe extraction: OK ({len(members)} entries)")
PY
