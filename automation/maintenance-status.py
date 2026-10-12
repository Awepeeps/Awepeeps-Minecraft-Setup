#!/usr/bin/env python3
"""Local read-only maintenance health; never prints journals or archive contents.

Configuration comes from the environment:
  BACKUP_ROOT        default /srv/minecraft/backups
  BACKUP_TIMEZONE    default UTC
  MAINTENANCE_UNITS  space-separated systemd user units, default
                     "mc-backup-test mc-backup-live mc-daily-reset"
"""
import datetime as dt
import os
from pathlib import Path
import stat
import subprocess
import sys
from zoneinfo import ZoneInfo

TIMEZONE = os.environ.get('BACKUP_TIMEZONE', 'UTC')
UNITS = os.environ.get('MAINTENANCE_UNITS', 'mc-backup-test mc-backup-live mc-daily-reset').split()


def backup_health(root, now):
    problems = []
    coverage = {}
    if root.is_symlink() or not root.is_dir():
        return {'daily': (0, 7), 'weekly': (0, 4)}, ['backup storage missing or invalid']
    for kind, expected in [('daily', 7), ('weekly', 4)]:
        directory = root / kind
        files = []
        if directory.is_symlink():
            problems.append(f'{kind}: storage is a symlink')
        elif directory.is_dir():
            if stat.S_IMODE(directory.stat().st_mode) & 0o077:
                problems.append(f'{kind}: directory permissions are not private')
            for path in directory.glob('world-*.tar.gz'):
                if path.is_symlink() or not path.is_file():
                    problems.append(f'{kind}: invalid archive type')
                    continue
                metadata = path.stat()
                if stat.S_IMODE(metadata.st_mode) & 0o077:
                    problems.append(f'{kind}: archive permissions are not private')
                files.append(metadata.st_mtime)
        dates = {dt.datetime.fromtimestamp(t, ZoneInfo(TIMEZONE)).date() for t in files}
        if kind == 'weekly':
            count = len({d.isocalendar()[:2] for d in dates})
        else:
            count = len(dates)
        coverage[kind] = (count, expected)
        if kind == 'daily' and (not files or now - max(files) > 36 * 3600):
            problems.append('daily: no backup in the last 36 hours')
    return coverage, problems


def main():
    issues = []
    root = Path(os.environ.get('BACKUP_ROOT', '/srv/minecraft/backups'))
    if root.is_symlink() or not root.is_dir():
        pass  # backup_health reports invalid storage without following it.
    elif stat.S_IMODE(root.stat().st_mode) & 0o077:
        issues.append('backup root permissions are not private')
    coverage, problems = backup_health(root, dt.datetime.now().timestamp())
    issues.extend(problems)
    for kind, (count, expected) in coverage.items():
        print(f'{kind} recovery coverage: {count}/{expected} distinct periods (accumulates over time)')
    for name in UNITS:
        try:
            result = subprocess.run(['systemctl', '--user', 'show', name + '.service',
                                     '-p', 'Result', '-p', 'ExecMainStatus'],
                                    capture_output=True, text=True, timeout=5, check=True)
            state = dict(line.split('=', 1) for line in result.stdout.splitlines() if '=' in line)
            healthy = state.get('Result') == 'success' and state.get('ExecMainStatus') == '0'
            timer = subprocess.run(['systemctl', '--user', 'is-active', name + '.timer'],
                                   capture_output=True, text=True, timeout=5)
            active = timer.returncode == 0 and timer.stdout.strip() == 'active'
            print(f'{name}: last result={"success" if healthy else "failed or unknown"}; timer={"active" if active else "inactive"}')
            if not healthy or not active:
                issues.append(f'{name}: requires attention')
        except (subprocess.SubprocessError, OSError):
            issues.append(f'{name}: state unavailable')
    for issue in issues:
        print('ATTENTION: ' + issue)
    print('Local inspection only; no external notifications or uploads.')
    return int(bool(issues))


if __name__ == '__main__':
    sys.exit(main())
