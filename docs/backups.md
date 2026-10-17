# Backups and restore

Backups are private data: they contain `server.properties` (and therefore the
RCON secret), plugin data, and EssentialsX per-player userdata. That userdata
may include nicknames, balances, homes, and locations. Keep `BACKUP_ROOT`
outside Git, outside the server data directory, and with owner-only permissions.
The scripts use `umask 077`,
create archives as mode 0600, and expect private directories (0700). Never copy
an archive into a public repository.

## Taking a backup

`automation/backup.sh` is live-safe: it never stops the server. It:

1. confirms the exact host directory is bind-mounted into the container at
   `DATA_DEST` (`/data`) and that the container is running,
2. acquires the shared lifecycle lock (so it cannot overlap a reset),
3. broadcasts, runs `save-off`, flushes saves, archives the world and the
   explicitly allowlisted plugin data,
4. always attempts `save-on` again on every exit path,
5. validates the archive and only then publishes it atomically,
6. rotates daily and weekly archives.

```bash
SERVER_DIR=/srv/minecraft/instances/<instance-data> \
BACKUP_ROOT=/srv/minecraft/backups \
  bash automation/backup.sh
```

Retention keeps the newest archive from each of `KEEP_DAILY` (default 7) distinct
dates and `KEEP_WEEKLY` (default 4) distinct ISO weeks. The timestamp uses
`BACKUP_TIMEZONE`.

## Verifying an archive

`automation/backup-verify.sh` validates integrity and path safety offline and
extracts into a temporary directory. It never touches the live server.

```bash
BACKUP_ROOT=/srv/minecraft/backups bash automation/backup-verify.sh
# or a specific archive:
bash automation/backup-verify.sh /srv/minecraft/backups/daily/world-YYYYMMDD-HHMMSS.tar.gz
```

It rejects traversal, links and special files, requires `world/level.dat` and
non-empty region data for every dimension, and then extracts. This proves archive
integrity and safe extraction; it is **not** a boot test.

The default plugin-data scope includes the BlueMap Compass and Spawn Kit data
directories, plus only `plugins/Essentials/config.yml`,
`plugins/Essentials/userdata/`, Geyser's `plugins/Geyser-Spigot/config.yml`, and
Geyser's `plugins/Geyser-Spigot/nethernet/` directory. The main EssentialsX
config is included; other EssentialsX files and directories such as kits, logs,
and other configuration files are excluded. Per-player state may still contain
economy or location data. Geyser's `nethernet/identity.pem` operator key is a
private key: keep it in the backup (losing it re-prompts every Bedrock player)
but never in Git. Keep `.env`'s `PLUGIN_DATA_DIRS` and `PLUGIN_DATA_PATHS` aligned
with `backup-verify.sh`; the verifier refuses unexpected plugin files.

The default allowlist does not include BlueMap Offline Player Markers. If you
change its settings from the published template defaults, add only
`plugins/BlueMapOfflinePlayerMarkers/config.yml` to `PLUGIN_DATA_PATHS` for both
backup and verification. Its `cachedPlayerNames.json` is derived data and need
not be backed up; Minecraft world player-data files remain the source of truth
for saved locations. Player identities and positions are private. BlueMap's
freeze state is in `<BLUEMAP_DATA>/pluginState.json`, with the data directory
selected by `core.data`; the current stock plugin-path allowlist does not capture
it. A deployment using frozen terrain batches must explicitly preserve that
single state file in its private backup and verifier, or re-freeze all maps
before exposing the viewer after restore.

## Scheduling

Use one scheduler. A systemd **user** timer is recommended, with an explicit
timezone and `Persistent=false` (a missed run must not replay later and capture a
surprising world). The script talks to the running container only; it never
starts or stops it.

Example unit values:

```ini
[Service]
Environment=SERVER_DIR=/srv/minecraft/instances/<instance-data>
Environment=CONTAINER=minecraft
Environment=BACKUP_ROOT=/srv/minecraft/backups
Environment=BACKUP_TIMEZONE=Etc/UTC
ExecStart=/usr/bin/bash /srv/minecraft/setup/automation/backup-scheduled.sh
```

Set `BACKUP_PHASE=test` before your cutoff date and `BACKUP_PHASE=live` on/after
it; the phase wrapper runs only the matching timer and does nothing while its
phase is inactive. Do **not** schedule backups as an MCSManager task: the panel's
managed lifecycle may remove the Docker container after it exits.

## Restore

1. Stop the instance from the panel.
2. Preserve the current data directory (copy it aside) before changing anything.
3. Verify the archive with `backup-verify.sh`, then extract it into a separate
   staging directory and check that the worlds, `server.properties`, and
   expected plugin state are present.
4. Move the restored files into the instance data path.
5. Reopen the instance **from the panel's lifecycle** — never `docker start` an
   MCSManager-managed container, because the panel may remove it after exit.

For a boot rehearsal, use a separate, isolated test server with the exact recorded
Paper build and Java version, **no published ports and no live data mount**, in a
temporary scratch directory. Remove the test container and scratch data afterward.

## Reading local status

`automation/maintenance-report.sh` prints a local, aggregate health summary: it
reads backup privacy/coverage and the last result of the configured systemd units
(`MAINTENANCE_UNITS`). It prints aggregate status only and never sends anything
externally.

```bash
BACKUP_ROOT=/srv/minecraft/backups MAINTENANCE_UNITS="mc-backup-test mc-backup-live mc-daily-reset" \
  bash automation/maintenance-report.sh
```

Recovery coverage accumulates over time; an incomplete count is a note for
follow-up, not necessarily an error. A successful backup alone does not prove
seven days of history or a successful restore.
