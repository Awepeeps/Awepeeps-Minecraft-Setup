#!/usr/bin/env python3
"""Point each BlueMap map at the current world spawn and enforce the inhabited-time policy.

The guarded disposable-world reset regenerates the world with a new seed, so the
overworld spawn moves and BlueMap's per-map ``start-pos`` (default ``0 0``) opens
the viewer on unrendered void. This tool reads the fresh world's spawn from
``world/level.dat`` (gzip NBT) and rewrites only the ``start-pos`` and
``min-inhabited-time`` lines of the generated ``plugins/BlueMap/maps/*.conf``
files. Run it read-only with ``--check``; ``--apply`` edits each file atomically
(temp file + rename, original mode and owner preserved). It never touches any
other line, and it fails closed without editing when a required line is missing
or ambiguous.

The server directory is passed with ``--server-dir`` (the container's ``/data``
mount); nothing here is instance-specific. See docs/bluemap.md.
"""

from __future__ import annotations

import argparse
import gzip
import os
import re
import stat
import struct
import sys
import tempfile
from pathlib import Path
from typing import NamedTuple

# Map id -> whether its start-pos tracks the overworld spawn. The End stays at 0,0.
MAPS: tuple[tuple[str, bool], ...] = (
    ("world", True),
    ("world_the_nether", True),
    ("world_the_end", False),
)
NETHER_COORDINATE_DIVISOR = 8
DEFAULT_MIN_INHABITED_TIME = 1200  # ticks (60 seconds) a chunk must accrue within simulation distance

START_POS_RE = re.compile(
    r"^start-pos:\s*\{\s*x:\s*(-?\d+)\s*,\s*z:\s*(-?\d+)\s*\}\s*$"
)
MIN_INHABITED_TIME_RE = re.compile(r"^min-inhabited-time:\s*(-?\d+)\s*$")

# NBT tag ids used by the level.dat reader.
_TAG_BYTE = 1
_TAG_SHORT = 2
_TAG_INT = 3
_TAG_LONG = 4
_TAG_FLOAT = 5
_TAG_DOUBLE = 6
_TAG_BYTE_ARRAY = 7
_TAG_STRING = 8
_TAG_LIST = 9
_TAG_COMPOUND = 10
_TAG_INT_ARRAY = 11
_TAG_LONG_ARRAY = 12
_MAX_NBT_DEPTH = 64


class Spawn(NamedTuple):
    x: int
    z: int
    layout: str


class MapPlan(NamedTuple):
    name: str
    path: Path
    start_pos: tuple[int, int]
    min_inhabited_time: int
    new_start_pos: tuple[int, int] | None


class Plan(NamedTuple):
    server_dir: Path
    spawn: Spawn | None
    spawn_error: str | None
    target_min_inhabited_time: int
    maps: list[MapPlan]
    edits: list[tuple[str, Path, str]]


def nether_coordinate(value: int) -> int:
    """Floor-divide an overworld coordinate the way Minecraft maps the Nether."""
    return value // NETHER_COORDINATE_DIVISOR


# --- level.dat (gzip NBT) reader -------------------------------------------------


def _take(raw: bytes, pos: int, count: int) -> tuple[bytes, int]:
    end = pos + count
    if count < 0 or end > len(raw):
        raise ValueError("truncated NBT data")
    return raw[pos:end], end


def _read_u1(raw: bytes, pos: int) -> tuple[int, int]:
    chunk, pos = _take(raw, pos, 1)
    return chunk[0], pos


def _read_string(raw: bytes, pos: int) -> tuple[str, int]:
    if pos + 2 > len(raw):
        raise ValueError("truncated NBT string length")
    length = struct.unpack_from(">H", raw, pos)[0]
    pos += 2
    chunk, pos = _take(raw, pos, length)
    return chunk.decode("utf-8", "strict"), pos


def _read_payload(raw: bytes, tag: int, pos: int, depth: int) -> tuple[object, int]:
    if depth > _MAX_NBT_DEPTH:
        raise ValueError("NBT nesting is too deep")
    if tag == _TAG_BYTE:
        return struct.unpack_from(">b", raw, pos)[0], pos + 1
    if tag == _TAG_SHORT:
        return struct.unpack_from(">h", raw, pos)[0], pos + 2
    if tag == _TAG_INT:
        return struct.unpack_from(">i", raw, pos)[0], pos + 4
    if tag == _TAG_LONG:
        return struct.unpack_from(">q", raw, pos)[0], pos + 8
    if tag == _TAG_FLOAT:
        return struct.unpack_from(">f", raw, pos)[0], pos + 4
    if tag == _TAG_DOUBLE:
        return struct.unpack_from(">d", raw, pos)[0], pos + 8
    if tag == _TAG_BYTE_ARRAY:
        length = struct.unpack_from(">i", raw, pos)[0]
        chunk, pos = _take(raw, pos + 4, length)
        return chunk, pos
    if tag == _TAG_STRING:
        return _read_string(raw, pos)
    if tag == _TAG_LIST:
        item_tag, pos = _read_u1(raw, pos)
        if pos + 4 > len(raw):
            raise ValueError("truncated NBT list length")
        length = struct.unpack_from(">i", raw, pos)[0]
        pos += 4
        if length < 0:
            return [], pos
        values = []
        for _ in range(length):
            value, pos = _read_payload(raw, item_tag, pos, depth + 1)
            values.append(value)
        return values, pos
    if tag == _TAG_COMPOUND:
        result: dict[str, object] = {}
        while True:
            child_tag, pos = _read_u1(raw, pos)
            if child_tag == 0:
                return result, pos
            name, pos = _read_string(raw, pos)
            value, pos = _read_payload(raw, child_tag, pos, depth + 1)
            result[name] = value
    if tag == _TAG_INT_ARRAY:
        if pos + 4 > len(raw):
            raise ValueError("truncated NBT int array length")
        length = struct.unpack_from(">i", raw, pos)[0]
        pos += 4
        if length < 0:
            raise ValueError("negative NBT int array length")
        return list(struct.unpack_from(f">{length}i", raw, pos)), pos + 4 * length
    if tag == _TAG_LONG_ARRAY:
        if pos + 4 > len(raw):
            raise ValueError("truncated NBT long array length")
        length = struct.unpack_from(">i", raw, pos)[0]
        pos += 4
        if length < 0:
            raise ValueError("negative NBT long array length")
        return list(struct.unpack_from(f">{length}q", raw, pos)), pos + 8 * length
    raise ValueError(f"unsupported NBT tag {tag}")


def parse_nbt(raw: bytes) -> dict[str, object]:
    """Parse one uncompressed NBT document whose root is a compound."""
    tag, pos = _read_u1(raw, 0)
    if tag != _TAG_COMPOUND:
        raise ValueError("NBT root is not a compound")
    _, pos = _read_string(raw, pos)
    root, _ = _read_payload(raw, _TAG_COMPOUND, pos, 0)
    assert isinstance(root, dict)
    return root


def _is_int(value: object) -> bool:
    return isinstance(value, int) and not isinstance(value, bool)


def extract_spawn(level_dat: dict[str, object]) -> Spawn:
    """Return the overworld spawn, preferring the 1.21.2+ ``spawn.pos`` layout."""
    data = level_dat.get("Data")
    if not isinstance(data, dict):
        raise ValueError("level.dat root has no Data compound")
    spawn = data.get("spawn")
    if spawn is not None:
        if not isinstance(spawn, dict):
            raise ValueError("level.dat Data.spawn field is not a compound")
        pos = spawn.get("pos")
        if pos is None:
            raise ValueError("level.dat Data.spawn compound has no pos array")
        if not isinstance(pos, list) or len(pos) < 3 or not all(_is_int(v) for v in pos[:3]):
            raise ValueError("level.dat Data.spawn.pos is not an integer x/y/z array")
        return Spawn(int(pos[0]), int(pos[2]), "spawn.pos")
    spawn_x = data.get("SpawnX")
    spawn_z = data.get("SpawnZ")
    if _is_int(spawn_x) and _is_int(spawn_z):
        return Spawn(int(spawn_x), int(spawn_z), "SpawnX/SpawnZ")
    raise ValueError("level.dat has neither a Data.spawn.pos array nor Data.SpawnX/SpawnZ fields")


def read_level_dat_spawn(path: Path) -> Spawn:
    if path.is_symlink():
        raise ValueError("world/level.dat must not be a symlink")
    if not path.is_file():
        raise ValueError("world/level.dat is missing")
    try:
        with gzip.open(path, "rb") as stream:
            raw = stream.read()
    except OSError as error:
        raise ValueError(f"world/level.dat is not readable gzip data: {error}")
    return extract_spawn(parse_nbt(raw))


# --- map-config line editing -----------------------------------------------------


def _replace_single_line(text: str, pattern: re.Pattern[str], replacement: str, label: str) -> str:
    matches = 0
    output = []
    for line in text.splitlines(keepends=True):
        body = line.rstrip("\r\n")
        if pattern.fullmatch(body):
            matches += 1
            output.append(replacement + line[len(body):])
        else:
            output.append(line)
    if matches != 1:
        raise ValueError(f"expected exactly one {label} line, found {matches}")
    return "".join(output)


def get_start_pos(text: str) -> tuple[int, int]:
    matches = [line for line in text.splitlines() if START_POS_RE.fullmatch(line.rstrip("\r\n"))]
    if len(matches) != 1:
        raise ValueError(f"expected exactly one start-pos line, found {len(matches)}")
    match = START_POS_RE.fullmatch(matches[0].rstrip("\r\n"))
    assert match is not None
    return int(match.group(1)), int(match.group(2))


def set_start_pos(text: str, x: int, z: int) -> str:
    return _replace_single_line(text, START_POS_RE, f"start-pos: {{ x: {x}, z: {z} }}", "start-pos")


def get_min_inhabited_time(text: str) -> int:
    matches = [line for line in text.splitlines() if MIN_INHABITED_TIME_RE.fullmatch(line.rstrip("\r\n"))]
    if len(matches) != 1:
        raise ValueError(f"expected exactly one min-inhabited-time line, found {len(matches)}")
    match = MIN_INHABITED_TIME_RE.fullmatch(matches[0].rstrip("\r\n"))
    assert match is not None
    return int(match.group(1))


def set_min_inhabited_time(text: str, ticks: int) -> str:
    return _replace_single_line(
        text, MIN_INHABITED_TIME_RE, f"min-inhabited-time: {ticks}", "min-inhabited-time"
    )


# --- safe, atomic file handling --------------------------------------------------


def resolve_server_dir(server_dir: Path) -> Path:
    if server_dir.is_symlink():
        raise ValueError("server directory must not be a symlink")
    try:
        base = server_dir.resolve(strict=True)
    except OSError as error:
        raise ValueError(f"server directory is not usable: {error}")
    if not base.is_dir():
        raise ValueError("server directory is not a directory")
    return base


def require_regular_file(path: Path, base: Path, label: str) -> Path:
    if path.is_symlink():
        raise ValueError(f"{label} must not be a symlink")
    try:
        resolved = path.resolve(strict=True)
    except OSError as error:
        raise ValueError(f"{label} is missing: {error}")
    if not resolved.is_relative_to(base) or not resolved.is_file():
        raise ValueError(f"{label} must be a regular file under the server directory")
    if resolved.stat().st_nlink != 1:
        raise ValueError(f"{label} must not be hard-linked")
    return resolved


def atomic_replace(path: Path, payload: bytes) -> None:
    """Replace a file in place, preserving its permission bits and owner."""
    info = path.stat()
    fd, temporary = tempfile.mkstemp(prefix=f".{path.name}.", dir=path.parent)
    try:
        with os.fdopen(fd, "wb") as stream:
            stream.write(payload)
            stream.flush()
            os.fsync(stream.fileno())
        os.chmod(temporary, stat.S_IMODE(info.st_mode))
        try:
            os.chown(temporary, info.st_uid, info.st_gid)
        except OSError:
            pass
        os.replace(temporary, path)
    except BaseException:
        try:
            os.unlink(temporary)
        except FileNotFoundError:
            pass
        raise


# --- planning and applying -------------------------------------------------------


def plan(server_dir: Path, min_inhabited_time: int) -> Plan:
    base = resolve_server_dir(server_dir)
    maps_dir = base / "plugins" / "BlueMap" / "maps"

    spawn: Spawn | None
    spawn_error: str | None
    try:
        spawn = read_level_dat_spawn(base / "world" / "level.dat")
        spawn_error = None
    except (OSError, UnicodeError, ValueError, struct.error) as error:
        spawn = None
        spawn_error = str(error)

    maps: list[MapPlan] = []
    edits: list[tuple[str, Path, str]] = []
    for name, tracks_spawn in MAPS:
        path = require_regular_file(maps_dir / f"{name}.conf", base, f"{name} map config")
        text = path.read_text(encoding="utf-8", errors="strict")
        current_start = get_start_pos(text)
        current_min = get_min_inhabited_time(text)

        new_start: tuple[int, int] | None = None
        if tracks_spawn and spawn is not None:
            if name == "world":
                new_start = (spawn.x, spawn.z)
            else:
                new_start = (nether_coordinate(spawn.x), nether_coordinate(spawn.z))

        updated = text
        if new_start is not None:
            updated = set_start_pos(updated, *new_start)
        updated = set_min_inhabited_time(updated, min_inhabited_time)

        maps.append(MapPlan(name, path, current_start, current_min, new_start))
        if updated != text:
            edits.append((name, path, updated))

    return Plan(base, spawn, spawn_error, min_inhabited_time, maps, edits)


def apply_plan(result: Plan) -> None:
    for _, path, updated in result.edits:
        atomic_replace(path, updated.encode("utf-8"))


def format_report(result: Plan, applying: bool) -> str:
    lines = [f"server dir: {result.server_dir}"]
    if result.spawn is not None:
        lines.append(
            f"spawn: world/level.dat x={result.spawn.x} z={result.spawn.z} (layout {result.spawn.layout})"
        )
    else:
        lines.append(f"spawn: unavailable ({result.spawn_error})")
    for plan_item in result.maps:
        current_x, current_z = plan_item.start_pos
        current = f"{{ x: {current_x}, z: {current_z} }}"
        if plan_item.new_start_pos is None:
            lines.append(f"  {plan_item.name}: start-pos {current} (unchanged)")
        else:
            new_x, new_z = plan_item.new_start_pos
            if (current_x, current_z) == (new_x, new_z):
                lines.append(f"  {plan_item.name}: start-pos {current} (unchanged)")
            else:
                lines.append(f"  {plan_item.name}: start-pos {current} -> {{ x: {new_x}, z: {new_z} }}")
    for plan_item in result.maps:
        target = result.target_min_inhabited_time
        if plan_item.min_inhabited_time == target:
            lines.append(f"  {plan_item.name}: min-inhabited-time {plan_item.min_inhabited_time} (unchanged)")
        else:
            lines.append(f"  {plan_item.name}: min-inhabited-time {plan_item.min_inhabited_time} -> {target}")
    verb = "updated" if applying else "pending"
    lines.append(f"{'apply' if applying else 'check'}: {len(result.edits)} file(s) {verb}")
    if applying and result.edits:
        lines.append("run 'rcon-cli bluemap reload' on the server to apply the map settings")
    return "\n".join(lines)


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    mode = parser.add_mutually_exclusive_group(required=True)
    mode.add_argument("--check", action="store_true", help="report the detected spawn and pending changes without writing")
    mode.add_argument("--apply", action="store_true", help="atomically update the BlueMap map configs")
    parser.add_argument("--server-dir", required=True, type=Path, help="Minecraft instance data directory (the container's /data mount)")
    parser.add_argument(
        "--min-inhabited-time",
        type=int,
        default=DEFAULT_MIN_INHABITED_TIME,
        help=f"chunk inhabited-time threshold in ticks (default {DEFAULT_MIN_INHABITED_TIME})",
    )
    args = parser.parse_args(argv)
    if args.min_inhabited_time < 0:
        parser.error("--min-inhabited-time must be a non-negative integer")

    try:
        result = plan(args.server_dir, args.min_inhabited_time)
    except (OSError, UnicodeError, ValueError, struct.error) as error:
        print(f"bluemap-spawn-view: {error}", file=sys.stderr)
        return 1

    if args.apply:
        try:
            apply_plan(result)
        except OSError as error:
            print(f"bluemap-spawn-view: could not write map config: {error}", file=sys.stderr)
            return 1

    print(format_report(result, applying=args.apply))
    if result.spawn_error is not None:
        print(
            f"bluemap-spawn-view: {result.spawn_error}; start-pos left unchanged",
            file=sys.stderr,
        )
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
