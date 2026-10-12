#!/usr/bin/env python3
"""Focused security checks for snapshot-policy.py."""

import importlib.util
import json
import os
import tempfile
import unittest
from pathlib import Path


MODULE_PATH = Path(__file__).with_name("snapshot-policy.py")
SPEC = importlib.util.spec_from_file_location("snapshot_policy", MODULE_PATH)
policy_module = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(policy_module)


class SnapshotPolicyTests(unittest.TestCase):
    def test_only_allowlisted_validated_policy_is_exported(self):
        parsed = policy_module.parse_properties(
            "white-list=true\n"
            "difficulty=HARD\n"
            "view-distance=10\n"
            "server-ip=203.0.113.44\n"
            "motd=Private family server\n"
            "level-seed=private-seed\n"
            "rcon.password=secret-value\n"
        )
        result = policy_module.build_policy(parsed)
        self.assertEqual(result, {"schema_version": 1, "policy": {
            "white-list": True, "difficulty": "hard", "view-distance": 10,
        }})
        encoded = json.dumps(result)
        for excluded in ("203.0.113.44", "Private family server", "private-seed", "secret-value"):
            self.assertNotIn(excluded, encoded)

    def test_rejects_injection_in_boolean_numeric_and_enum_values(self):
        for key, value in (("white-list", "true\nserver-ip=192.0.2.1"),
                           ("view-distance", "10;motd=leak"),
                           ("difficulty", "hard, player=identity")):
            with self.subTest(key=key), self.assertRaises(ValueError):
                policy_module.build_policy({key: value})

    def test_rejects_out_of_range_number_and_slug_traversal(self):
        with self.assertRaises(ValueError):
            policy_module.build_policy({"view-distance": "99"})
        for value in ("../other", "Fall-26", "one/two", "a..b"):
            with self.subTest(value=value), self.assertRaises(ValueError):
                policy_module.validate_slug(value, "season slug")

    def test_refuses_symlink_source(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            server = root / "server"
            server.mkdir()
            outside = root / "outside.properties"
            outside.write_text("white-list=true\n", encoding="utf-8")
            link = server / "server.properties"
            try:
                link.symlink_to(outside)
            except (OSError, NotImplementedError):
                self.skipTest("symlinks are unavailable")
            with self.assertRaises(ValueError):
                policy_module.safe_source(server, "server.properties")

    def test_refuses_server_directory_symlink(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            real = root / "real"
            real.mkdir()
            (real / "server.properties").write_text("white-list=true\n", encoding="utf-8")
            link = root / "server-link"
            try:
                link.symlink_to(real, target_is_directory=True)
            except (OSError, NotImplementedError):
                self.skipTest("symlinks are unavailable")
            with self.assertRaises(ValueError):
                policy_module.safe_source(link, "server.properties")

    def test_atomic_write_stays_inside_repo_and_sets_private_mode(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            repo = root / "repo"
            repo.mkdir()
            target = repo / "season" / "policy.json"
            policy_module.atomic_write(repo, target, b'{"policy":{}}\n')
            self.assertEqual(target.read_bytes(), b'{"policy":{}}\n')
            self.assertEqual(target.stat().st_mode & 0o777, 0o600)
            self.assertEqual(list(target.parent.glob(".snapshot-policy-*")), [])

            outside = root / "outside.json"
            with self.assertRaises(ValueError):
                policy_module.atomic_write(repo, outside, b"{}")

    def test_rejects_symlink_parent_before_creating_outside_directories(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            repo = root / "repo"
            outside = root / "outside"
            repo.mkdir()
            outside.mkdir()
            link = repo / "seasons"
            try:
                link.symlink_to(outside, target_is_directory=True)
            except (OSError, NotImplementedError):
                self.skipTest("symlinks are unavailable")
            target = link / "new-server" / "new-season" / "policy.json"
            with self.assertRaises(ValueError):
                policy_module.atomic_write(repo, target, b"{}")
            self.assertEqual(list(outside.iterdir()), [])

    def test_rejects_dangling_symlink_output(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            repo = root / "repo"
            repo.mkdir()
            target = repo / "policy.json"
            try:
                target.symlink_to(root / "missing")
            except (OSError, NotImplementedError):
                self.skipTest("symlinks are unavailable")
            with self.assertRaises(ValueError):
                policy_module.atomic_write(repo, target, b"{}")


if __name__ == "__main__":
    unittest.main(verbosity=2)
