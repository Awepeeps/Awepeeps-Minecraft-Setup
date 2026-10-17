#!/usr/bin/env python3
"""Focused checks for bluemap-spawn-view.py (NBT layouts, line edits, fail-closed apply).

No Docker, network, or live server is contacted. Run via automation/run-tests.sh.
"""

import contextlib
import gzip
import importlib.util
import io
import stat
import struct
import tempfile
import unittest
from pathlib import Path


MODULE_PATH = Path(__file__).with_name("bluemap-spawn-view.py")
SPEC = importlib.util.spec_from_file_location("bluemap_spawn_view", MODULE_PATH)
spawn_view = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(spawn_view)

TAG_INT = 3
TAG_STRING = 8
TAG_COMPOUND = 10
TAG_INT_ARRAY = 11
TAG_FLOAT = 5


def _nbt_string(value):
    data = value.encode("utf-8")
    return struct.pack(">H", len(data)) + data


def _nbt_payload(tag, value):
    if tag == 1:
        return struct.pack(">b", value)
    if tag == 2:
        return struct.pack(">h", value)
    if tag == 3:
        return struct.pack(">i", value)
    if tag == 4:
        return struct.pack(">q", value)
    if tag == 5:
        return struct.pack(">f", value)
    if tag == 6:
        return struct.pack(">d", value)
    if tag == TAG_STRING:
        return _nbt_string(value)
    if tag == 7:
        return struct.pack(">i", len(value)) + bytes(value)
    if tag == 9:
        item_tag, items = value
        out = bytes([item_tag]) + struct.pack(">i", len(items))
        for item in items:
            out += _nbt_payload(item_tag, item)
        return out
    if tag == TAG_COMPOUND:
        out = b""
        for key, (child_tag, child_value) in value.items():
            out += _nbt_tagged(child_tag, key, child_value)
        return out + b"\x00"
    if tag == TAG_INT_ARRAY:
        return struct.pack(">i", len(value)) + struct.pack(f">{len(value)}i", *value)
    if tag == 12:
        return struct.pack(">i", len(value)) + struct.pack(f">{len(value)}q", *value)
    raise AssertionError(f"unsupported test NBT tag {tag}")


def _nbt_tagged(tag, name, value):
    return bytes([tag]) + _nbt_string(name) + _nbt_payload(tag, value)


def level_dat_bytes(data_entries):
    return gzip.compress(_nbt_tagged(TAG_COMPOUND, "", {"Data": (TAG_COMPOUND, data_entries)}))


def new_layout_entries(x=320, y=68, z=464):
    return {
        "spawn": (TAG_COMPOUND, {
            "pos": (TAG_INT_ARRAY, [x, y, z]),
            "pitch": (TAG_FLOAT, 0.0),
            "yaw": (TAG_FLOAT, 0.0),
            "dimension": (TAG_STRING, "minecraft:overworld"),
        }),
        "LevelName": (TAG_STRING, "world"),
    }


def legacy_layout_entries(x=-704, y=66, z=192):
    return {
        "SpawnX": (TAG_INT, x),
        "SpawnY": (TAG_INT, y),
        "SpawnZ": (TAG_INT, z),
        "LevelName": (TAG_STRING, "world"),
    }


def conf_text(x=0, z=0, min_time=30, include_start=True, include_min=True):
    lines = [
        "## BlueMap map-config (generated)",
        "# The position in the world where the map will be centered on when you open it.",
        "# Default is { x: 0, z: 0 }",
    ]
    if include_start:
        lines.append(f"start-pos: {{ x: {x}, z: {z} }}")
    if include_min:
        lines.append("# Default is 0 (all generated chunks).")
        lines.append(f"min-inhabited-time: {min_time}")
    return "\n".join(lines) + "\n"


def build_server_dir(root, *, spawn_entries, world_text=None, nether_text=None, end_text=None):
    server = root / "server"
    (server / "world").mkdir(parents=True)
    maps = server / "plugins" / "BlueMap" / "maps"
    maps.mkdir(parents=True)
    (server / "world" / "level.dat").write_bytes(level_dat_bytes(spawn_entries))
    (maps / "world.conf").write_text(world_text if world_text is not None else conf_text(), encoding="utf-8")
    (maps / "world_the_nether.conf").write_text(
        nether_text if nether_text is not None else conf_text(), encoding="utf-8"
    )
    (maps / "world_the_end.conf").write_text(
        end_text if end_text is not None else conf_text(), encoding="utf-8"
    )
    return server, maps


class BluemapSpawnViewTests(unittest.TestCase):
    def test_reads_new_spawn_pos_layout(self):
        with tempfile.TemporaryDirectory() as temp:
            level = Path(temp) / "level.dat"
            level.write_bytes(level_dat_bytes(new_layout_entries(320, 68, 464)))
            spawn = spawn_view.read_level_dat_spawn(level)
            self.assertEqual((spawn.x, spawn.z, spawn.layout), (320, 464, "spawn.pos"))

    def test_reads_legacy_spawn_fields(self):
        with tempfile.TemporaryDirectory() as temp:
            level = Path(temp) / "level.dat"
            level.write_bytes(level_dat_bytes(legacy_layout_entries(-704, 66, 192)))
            spawn = spawn_view.read_level_dat_spawn(level)
            self.assertEqual((spawn.x, spawn.z, spawn.layout), (-704, 192, "SpawnX/SpawnZ"))

    def test_missing_spawn_fails_closed(self):
        with tempfile.TemporaryDirectory() as temp:
            level = Path(temp) / "level.dat"
            level.write_bytes(level_dat_bytes({"LevelName": (TAG_STRING, "world")}))
            with self.assertRaisesRegex(ValueError, "neither a Data.spawn.pos array nor Data.SpawnX"):
                spawn_view.read_level_dat_spawn(level)

    def test_malformed_spawn_pos_fails_closed(self):
        with tempfile.TemporaryDirectory() as temp:
            level = Path(temp) / "level.dat"
            entries = {"spawn": (TAG_COMPOUND, {"pos": (TAG_STRING, "not-an-array")})}
            level.write_bytes(level_dat_bytes(entries))
            with self.assertRaisesRegex(ValueError, "not an integer x/y/z array"):
                spawn_view.read_level_dat_spawn(level)

    def test_not_gzip_fails_closed(self):
        with tempfile.TemporaryDirectory() as temp:
            level = Path(temp) / "level.dat"
            level.write_bytes(b"not gzip data")
            with self.assertRaises(ValueError):
                spawn_view.read_level_dat_spawn(level)

    def test_nether_coordinate_floor_division(self):
        self.assertEqual(spawn_view.nether_coordinate(320), 40)
        self.assertEqual(spawn_view.nether_coordinate(464), 58)
        self.assertEqual(spawn_view.nether_coordinate(-704), -88)
        self.assertEqual(spawn_view.nether_coordinate(-705), -89)

    def test_set_start_pos_replaces_only_the_target_line(self):
        text = conf_text(0, 0)
        updated = spawn_view.set_start_pos(text, 320, 464)
        self.assertIn("start-pos: { x: 320, z: 464 }", updated)
        self.assertIn("# Default is { x: 0, z: 0 }", updated)  # comment untouched
        self.assertNotIn("start-pos: { x: 0, z: 0 }", updated)
        self.assertEqual(updated.count("\n"), text.count("\n"))
        self.assertEqual(spawn_view.get_start_pos(updated), (320, 464))

    def test_start_pos_requires_exactly_one_line(self):
        with self.assertRaisesRegex(ValueError, "expected exactly one start-pos line, found 0"):
            spawn_view.set_start_pos(conf_text(include_start=False), 1, 2)
        doubled = conf_text(0, 0) + "start-pos: { x: 1, z: 1 }\n"
        with self.assertRaisesRegex(ValueError, "expected exactly one start-pos line, found 2"):
            spawn_view.set_start_pos(doubled, 1, 2)

    def test_min_inhabited_time_edit_and_unique_requirement(self):
        updated = spawn_view.set_min_inhabited_time(conf_text(0, 0, min_time=30), 1200)
        self.assertIn("min-inhabited-time: 1200", updated)
        self.assertEqual(spawn_view.get_min_inhabited_time(updated), 1200)
        with self.assertRaisesRegex(ValueError, "expected exactly one min-inhabited-time line, found 0"):
            spawn_view.set_min_inhabited_time(conf_text(include_min=False), 1200)

    def test_apply_updates_maps_preserves_mode_and_is_idempotent(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            server, maps = build_server_dir(root, spawn_entries=new_layout_entries(320, 68, 464))
            for name in ("world", "world_the_nether", "world_the_end"):
                (maps / f"{name}.conf").chmod(0o664)

            result = spawn_view.plan(server, 1200)
            self.assertEqual(len(result.edits), 3)
            spawn_view.apply_plan(result)

            self.assertIn("start-pos: { x: 320, z: 464 }", (maps / "world.conf").read_text(encoding="utf-8"))
            self.assertIn(
                "start-pos: { x: 40, z: 58 }", (maps / "world_the_nether.conf").read_text(encoding="utf-8")
            )
            self.assertIn(
                "start-pos: { x: 0, z: 0 }", (maps / "world_the_end.conf").read_text(encoding="utf-8")
            )
            for name in ("world", "world_the_nether", "world_the_end"):
                path = maps / f"{name}.conf"
                self.assertIn("min-inhabited-time: 1200", path.read_text(encoding="utf-8"))
                self.assertEqual(stat.S_IMODE(path.stat().st_mode), 0o664)
            self.assertEqual(list(maps.glob(".*")), [])

            again = spawn_view.plan(server, 1200)
            self.assertEqual(again.edits, [])

    def test_apply_negative_spawn_uses_floor_division(self):
        with tempfile.TemporaryDirectory() as temp:
            server, maps = build_server_dir(
                Path(temp), spawn_entries=new_layout_entries(-705, 66, -705)
            )
            spawn_view.apply_plan(spawn_view.plan(server, 1200))
            self.assertIn(
                "start-pos: { x: -89, z: -89 }",
                (maps / "world_the_nether.conf").read_text(encoding="utf-8"),
            )

    def test_apply_fails_closed_without_start_pos(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            before = conf_text(0, 0)
            server, maps = build_server_dir(
                root, spawn_entries=new_layout_entries(), world_text=conf_text(include_start=False)
            )
            with self.assertRaises(ValueError):
                spawn_view.plan(server, 1200)
            # No file may be edited when any required line is missing.
            self.assertEqual((maps / "world_the_nether.conf").read_text(encoding="utf-8"), before)

    def test_spawn_failure_still_sets_min_inhabited_time(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            server, maps = build_server_dir(root, spawn_entries=new_layout_entries())
            (server / "world" / "level.dat").write_bytes(b"corrupt")
            result = spawn_view.plan(server, 1200)
            self.assertIsNotNone(result.spawn_error)
            self.assertEqual(len(result.edits), 3)
            spawn_view.apply_plan(result)
            self.assertIn("start-pos: { x: 0, z: 0 }", (maps / "world.conf").read_text(encoding="utf-8"))
            self.assertIn("min-inhabited-time: 1200", (maps / "world.conf").read_text(encoding="utf-8"))

    def test_refuses_symlinked_map_config(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            server, maps = build_server_dir(root, spawn_entries=new_layout_entries())
            outside = root / "outside.conf"
            outside.write_text(conf_text(), encoding="utf-8")
            target = maps / "world.conf"
            target.unlink()
            try:
                target.symlink_to(outside)
            except (OSError, NotImplementedError):
                self.skipTest("symlinks are unavailable")
            with self.assertRaisesRegex(ValueError, "must not be a symlink"):
                spawn_view.plan(server, 1200)

    def test_check_mode_writes_nothing(self):
        with tempfile.TemporaryDirectory() as temp:
            server, maps = build_server_dir(Path(temp), spawn_entries=new_layout_entries(320, 68, 464))
            before = (maps / "world.conf").read_text(encoding="utf-8")
            buffer = io.StringIO()
            with contextlib.redirect_stdout(buffer):
                code = spawn_view.main(["--check", "--server-dir", str(server)])
            self.assertEqual(code, 0)
            self.assertEqual((maps / "world.conf").read_text(encoding="utf-8"), before)
            self.assertIn("x=320 z=464", buffer.getvalue())

    def test_apply_mode_reports_error_when_spawn_missing(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            server, maps = build_server_dir(root, spawn_entries=new_layout_entries())
            (server / "world" / "level.dat").write_bytes(b"corrupt")
            buffer = io.StringIO()
            with contextlib.redirect_stdout(buffer):
                code = spawn_view.main(["--apply", "--server-dir", str(server)])
            self.assertEqual(code, 1)
            self.assertIn("min-inhabited-time: 1200", (maps / "world.conf").read_text(encoding="utf-8"))

    def test_mode_is_required(self):
        with self.assertRaises(SystemExit):
            spawn_view.main(["--server-dir", "."])


if __name__ == "__main__":
    unittest.main(verbosity=2)
