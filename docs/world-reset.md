# Guarded test-world reset

`automation/daily-reset.sh` wipes the world of a **disposable test server** and
reopens it, giving it a fresh world each run. It is designed to be safe against a
live server: it self-expires, takes a verified pre-wipe backup, and refuses to
change anything if a check fails.

> Never point this at a live season world. A live server keeps its world; the
> reset is for rehearsing the whitelist, Bedrock, plugin and upgrade flows.

## Safety properties

- **Self-expiring.** `RESET_UNTIL` is the date after which the job no-ops. On and
  after that date it exits before touching the state directory, server files or
  Docker. This prevents a test wipe from "forgetting" to stop.
- **Hard pre-wipe backup.** With `PREWIPE_BACKUP=1` (the default) it runs
  `backup.sh` under the same lifecycle lock and aborts the wipe if the backup
  fails. Never set it to 0 against real data.
- **One lifecycle lock.** Reset, backup, restore, recovery and season close all
  share `STATE_DIR/lifecycle.lock`. A job holds the lock before it inspects or
  changes lifecycle state and releases it on every exit path.
- **Exact mount check.** It verifies the configured host directory is the
  container's `/data` bind source before doing anything.
- **Fail closed.** A symlinked world/plugins/plugin-state path, a missing or
  malformed `server.properties` seed key, a failed RCON stop, a non-zero container
  exit, a failed gamerule verify, or an unacknowledged BlueMap purge stops the run
  before the seed index advances.
- **Deferred state removal.** Plugin state files are removed only after every
  world directory was deleted successfully, so a failed wipe cannot leave a
  surviving world that no longer re-issues state.

## What resets, what survives

| Reset each run | Survives |
|---|---|
| `world`, `world_nether`, `world_the_end` | plugin jars/configs, whitelist, ops, LuckPerms data |
| Awepeeps Spawn Kit `issued-kits.yml` (test only) | all other instance files |
| BlueMap Compass `banner-markers.yml` | other `server.properties` settings |
| `level-seed` (rotates through `automation/seeds.txt`, or empty for random) | |

`seeds.txt` holds one literal integer per line; blank lines and `#` comments are
ignored. An empty file means a fresh random seed each run.

## Running it

Configure the panel ids (from your MCSManager install) in the environment:

```bash
SERVER_DIR=/srv/minecraft/instances/<instance-data> \
CONTAINER=minecraft \
STATE_DIR=/srv/minecraft/.reset-state \
RESET_UNTIL=2026-11-28 \
MCSM_NODE_ID=<panel-node-id> \
MCSM_INSTANCE_UUID=<instance-id> \
  bash automation/daily-reset.sh
```

The script uses the image's internal `rcon-cli`; no RCON password is placed on
the command line or in configuration. After the wipe it asks MCSManager to reopen
the saved instance (via `automation/mcsm-start.js`), waits for RCON readiness, and
applies `minecraft:players_sleeping_percentage 50` in all three dimensions.

## BlueMap purge gate

When `plugins/BlueMap` is present, the reset runs `/bluemap purge` for every map
in `BLUEMAP_MAPS` and requires BlueMap's acknowledgment before the seed index is
advanced. If BlueMap is still loading it retries within `BLUEMAP_PURGE_TIMEOUT`.
An unacknowledged purge stops the run. See [bluemap.md](bluemap.md) for why an
idle/updated status is not proof the old tiles are gone.

## Spawn Kit preloading (test servers only)

Awepeeps-SpawnKit is test-only. When its config enables placement, the reset
temporarily forceloads a bounded area around the configured spawn so the plugin
can build before first login, waits up to `SPAWN_KIT_SETUP_TIMEOUT`, then removes
that temporary ticket. It never touches an existing forceload and never leaves
its own behind. Keep `SPAWN_KIT_LOAD_RADIUS` at least four blocks larger than the
plugin's `search-radius`; set `SPAWN_KIT_LOAD_X`/`_Z` if the spawn is not `0,0`.

## Stopping automatic recovery

`automation/recovery-gate.sh disable` writes a marker that tells any automatic
boot-recovery job to leave the server stopped. Re-enable it with
`automation/recovery-gate.sh enable`. Use it before an intentional stop so a
scheduled recovery does not race you.

## Scheduling

Run the reset from a systemd user timer with an explicit timezone and
`Persistent=false`, on the host (not as an MCSManager console task — it needs to
manage Docker and instance files). Schedule the backup timers around it. See
[backups.md](backups.md) for the unit pattern; use the same `SERVER_DIR`,
`CONTAINER`, `STATE_DIR` and panel ids.
