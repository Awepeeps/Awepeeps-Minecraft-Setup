import importlib.util
from pathlib import Path
import os
import tempfile
import unittest

spec = importlib.util.spec_from_file_location('status', Path(__file__).with_name('maintenance-status.py'))
status = importlib.util.module_from_spec(spec)
spec.loader.exec_module(status)


class HealthTests(unittest.TestCase):
    def test_symlink_root_is_never_scanned(self):
        with tempfile.TemporaryDirectory() as temporary:
            outside = Path(temporary) / 'outside'
            (outside / 'daily').mkdir(parents=True)
            (outside / 'daily' / 'world-synthetic.tar.gz').write_bytes(b'fixture')
            link = Path(temporary) / 'link'
            link.symlink_to(outside, target_is_directory=True)
            coverage, problems = status.backup_health(link, 0)
            self.assertEqual(coverage['daily'], (0, 7))
            self.assertEqual(problems, ['backup storage missing or invalid'])

    def test_missing_stale_and_insecure_archives_raise_attention(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            coverage, problems = status.backup_health(root, 200000)
            self.assertIn('daily: no backup in the last 36 hours', problems)
            directory = root / 'daily'
            directory.mkdir(mode=0o700)
            archive = directory / 'world-synthetic.tar.gz'
            archive.write_bytes(b'fixture')
            archive.chmod(0o600)
            os.utime(archive, (200000, 200000))
            coverage, problems = status.backup_health(root, 200000)
            self.assertEqual(coverage['daily'], (1, 7))
            self.assertEqual(problems, [])
            os.utime(archive, (1, 1))
            archive.chmod(0o644)
            _, problems = status.backup_health(root, 200000)
            self.assertIn('daily: no backup in the last 36 hours', problems)
            self.assertIn('daily: archive permissions are not private', problems)


if __name__ == '__main__':
    unittest.main()
