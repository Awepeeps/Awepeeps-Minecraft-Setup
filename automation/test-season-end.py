"""Exercise permanent-archive orchestration with isolated backup stubs only."""
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import time
import unittest


class SeasonEndTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        root = Path(self.tmp.name)
        self.repo = root / 'repo'
        self.automation = self.repo / 'automation'
        self.automation.mkdir(parents=True)
        self.season = self.repo / 'seasons/survival/test'
        self.season.mkdir(parents=True)
        (self.season / 'README.md').write_text('| End date | pending |\n')
        self.backups = root / 'private'
        self.state = root / '.reset-state'
        self.server = root / 'server'
        self.server.mkdir()
        shutil.copyfile(Path(__file__).with_name('season-end.sh'), self.automation / 'season-end.sh')
        stubs = {
            'backup.sh': '''#!/bin/bash
[[ "${BACKUP_LOCK_HELD:-}" == 1 ]] || exit 20
exec 8>>"$STATE_DIR/lifecycle.lock"
flock -n 8 && exit 21
echo called >> "$BACKUP_CALLS"
mkdir -p "$BACKUP_ROOT/daily"
printf fixture > "$BACKUP_ROOT/daily/world-20261011-000000.tar.gz"
''',
            'backup-verify.sh': '#!/bin/bash\n[[ $(cat "$1") == fixture ]]\n',
            'snapshot-to-git.sh': '''#!/bin/bash
if [[ "${BLOCK_SNAPSHOT:-}" == 1 ]]; then
  touch "$SNAPSHOT_STARTED"
  while [[ ! -e "$RELEASE_SNAPSHOT" ]]; do sleep 0.02; done
fi
exit 0
''',
        }
        for name, text in stubs.items():
            path = self.automation / name
            path.write_text(text)
            path.chmod(0o700)
        self.env = dict(os.environ, SERVER_DIR=str(self.server), REPO_DIR=str(self.repo),
                        BACKUP_ROOT=str(self.backups), STATE_DIR=str(self.state),
                        BACKUP_CALLS=str(root / 'backup-calls'), SERVER_SLUG='survival', SEASON_SLUG='test')

    def run_script(self):
        return subprocess.run(['bash', str(self.automation / 'season-end.sh')],
                              env=self.env, capture_output=True, text=True, timeout=10)

    def test_archive_is_private_outside_git_and_never_overwritten(self):
        self.assertEqual(self.run_script().returncode, 0)
        archive = self.backups / 'seasons/survival/test/world-final.tar.gz'
        self.assertEqual(archive.read_bytes(), b'fixture')
        self.assertEqual(archive.stat().st_mode & 0o777, 0o600)
        self.assertFalse((self.season / 'archive').exists())
        self.assertNotIn('pending', (self.season / 'README.md').read_text())
        archive.write_bytes(b'preserve')
        self.assertNotEqual(self.run_script().returncode, 0)
        self.assertEqual(archive.read_bytes(), b'preserve')

    def test_traversal_slug_is_rejected_before_backup(self):
        self.env['SEASON_SLUG'] = '../../escape'
        self.assertNotEqual(self.run_script().returncode, 0)
        self.assertFalse(self.backups.exists())

    def test_symlink_archive_directory_is_rejected(self):
        self.backups.mkdir()
        outside = Path(self.tmp.name) / 'outside'
        outside.mkdir()
        (self.backups / 'seasons').symlink_to(outside, target_is_directory=True)
        self.assertNotEqual(self.run_script().returncode, 0)
        self.assertEqual(list(outside.iterdir()), [])

    def test_rootlike_state_path_is_rejected_before_mutation_or_backup(self):
        self.env['STATE_DIR'] = '/'
        before_mode = Path('/').stat().st_mode & 0o777
        result = self.run_script()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('dedicated .reset-state', result.stderr)
        self.assertEqual(Path('/').stat().st_mode & 0o777, before_mode)
        self.assertFalse(Path(self.env['BACKUP_CALLS']).exists())

    def test_symlinked_state_ancestor_is_rejected_before_creation_or_chmod(self):
        real_parent = Path(self.tmp.name) / 'real-parent'
        real_parent.mkdir()
        real_parent.chmod(0o755)
        alias_parent = Path(self.tmp.name) / 'alias-parent'
        alias_parent.symlink_to(real_parent, target_is_directory=True)
        state_path = alias_parent / '.reset-state'
        self.env['STATE_DIR'] = str(state_path)
        before_mode = real_parent.stat().st_mode & 0o777
        result = self.run_script()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('unsafe state path', result.stderr)
        self.assertFalse(state_path.exists())
        self.assertEqual(real_parent.stat().st_mode & 0o777, before_mode)
        self.assertFalse(Path(self.env['BACKUP_CALLS']).exists())

    def test_new_backup_is_pinned_even_with_newer_mtime_existing_archive(self):
        daily = self.backups / 'daily'
        daily.mkdir(parents=True)
        old = daily / 'world-20991231-235959.tar.gz'
        old.write_bytes(b'old-preserve')
        os.utime(old, (4102444800, 4102444800))
        self.assertEqual(self.run_script().returncode, 0)
        archive = self.backups / 'seasons/survival/test/world-final.tar.gz'
        self.assertEqual(archive.read_bytes(), b'fixture')
        self.assertTrue((daily / 'world-20261011-000000.tar.gz').exists())

    def test_internal_lock_serializes_close_and_backup_inherits_held_contract(self):
        self.env.update(BACKUP_LOCK_HELD='1', BLOCK_SNAPSHOT='1', SNAPSHOT_STARTED=str(self.state / 'snapshot-started'),
                        RELEASE_SNAPSHOT=str(self.state / 'release-snapshot'))
        first = subprocess.Popen(['bash', str(self.automation / 'season-end.sh')], env=self.env,
                                 stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
        try:
            deadline = time.monotonic() + 5
            while time.monotonic() < deadline and not Path(self.env['SNAPSHOT_STARTED']).exists():
                time.sleep(0.02)
            self.assertTrue(Path(self.env['SNAPSHOT_STARTED']).exists(), 'first close did not reach snapshot')
            second = self.run_script()
            self.assertNotEqual(second.returncode, 0)
            self.assertIn('lifecycle busy', second.stderr)
            self.assertEqual(Path(self.env['BACKUP_CALLS']).read_text().splitlines(), ['called'])
        finally:
            Path(self.env['RELEASE_SNAPSHOT']).touch()
        out, err = first.communicate(timeout=5)
        self.assertEqual(first.returncode, 0, out + err)


if __name__ == '__main__':
    unittest.main()
