# BlueMap and the web map

BlueMap renders the world to a web map. Keep its endpoint private (LAN/VPN, or
behind a reverse proxy with TLS) until you have decided to expose it.

## Server settings

- `accept-download: true` in `plugins/BlueMap/core.conf` accepts Mojang's EULA,
  confirms a Java Edition license, and allows BlueMap to download and use
  Mojang's client resources for map textures. BlueMap cannot render without
  those resources. Review the statement BlueMap prints before accepting it.
- `plugins/BlueMap/webapp.conf`: port **8100**, with hires/lowres slider
  **min 0 / default 160 / max 160** and `max-zoom-distance: 512`. These are
  template values; confirm the exact key names against your BlueMap version's
  generated file (**TODO** — see `config/plugins/BlueMap/webapp.conf.template`).
- `max-zoom-distance: 512` matches player `view-distance 10`; it limits how far
  the 3D viewer can zoom out. It does not change Minecraft chunk delivery.
- Resolve the generated `webapp.conf` placeholders (`${webroot}`, `${logfile}`)
  to concrete paths so the built-in webserver starts.
- Publish port 8100/tcp on the instance and restart/recreate it from the panel.
  Verify `http://<SERVER_HOST>:8100/` returns the map after a render.

## Explored-terrain policy

Set `min-inhabited-time: 1200` in each map configuration
(`plugins/BlueMap/maps/<map-id>.conf`, for example `world`,
`world_the_nether`, `world_the_end`). A chunk accumulates inhabited time while a
player is nearby; at 20 game ticks per second, `1200` is about 60 seconds of
cumulative nearby time before BlueMap renders that chunk. Leave any
inhabited-time radius at its default zero.

Two values matter as a deliberate choice:

- `30` ticks (~1.5 seconds) renders almost everything a player walked past, so it
  barely filters the map.
- `1200` ticks (60 seconds) is an **explored-terrain filter**: chunks a player
  only rushed through are left undrawn, while places they spent time are drawn.
  The reference instance uses `1200`; the template header states the same value
  and the tradeoff.

Inhabited time counts **every chunk within a player's simulation distance**, not
only the chunks a client actually received. At `simulation-distance=8`
(8 chunks ≈ 128 blocks on each axis) a player still lights up roughly a
128-block radius, so the drawn radius around where people spent time cannot
shrink below that without lowering `simulation-distance` further. Minecraft's
`view-distance=10` is independent: it still controls how far a client receives
chunks and still matches the 160-block web-viewer draw cap below.

This is a **map-render threshold**, not an exact record of what a client saw:
nearby time can qualify a chunk, while client visibility and render timing are
separate. Changing it requires a map re-render. See the
[official map configuration reference](https://bluemap.bluecolored.de/wiki/configs/Maps.html).

## Scheduled terrain batches

BlueMap watches changed region files and queues terrain updates. To batch terrain
work, freeze every map before exposing the viewer, including each configured
dimension. The native freeze state persists across a server restart. For example,
from the server console:

```text
/bluemap maps
/bluemap freeze world
/bluemap freeze world_the_nether
/bluemap freeze world_the_end
```

Use the actual map IDs returned by `/bluemap maps`. Freezing each map is the
update gate: relying on the periodic full-update interval alone would leave its
region watcher active.

A batch runs the native `/bluemap update <map-id>` command once for each map.
This updates changed terrain and saves the world first. Do not substitute
`force-update`, which redraws even unchanged terrain. Before starting a batch,
check `/bluemap` and `/bluemap tasks`; run only when the render queue is idle and
do not overlap batches. Poll both status commands until the queue is idle again.
Bound each scheduled service to 900 seconds. If it times out or BlueMap reports a
render failure, record the failure and leave the map frozen for the next batch.

Use a host-side systemd user timer, with `Persistent=false`, to invoke the native
commands through the server's existing authenticated console or RCON path. For a
disposable test world, schedule hourly at minute 10 (`OnCalendar=*-*-* *:10:00`).
For a live world, schedule once daily before that host's morning backup. Keep
backup success independent of rendering: a sequential pre-backup wrapper can
wait for a bounded batch, warn on failure and still back up primary data. Do not
let a failed render skip that backup. Do not put RCON credentials in unit
files or command lines.

The live viewer's terrain is usually from the latest completed batch, so its age
varies from near zero to about 24 hours plus render time. This is an operating
cadence, not a strict freshness guarantee: a missed, timed-out, or failed batch
can leave older terrain visible. Live player markers, Compass waypoints, and
offline-player markers remain separate from the terrain schedule.

The guarded world-reset workflow purges each map's generated tiles. A frozen map
stays blank for terrain until the next scheduled `/bluemap update`; this is
expected. Checkpoints after restore matter too: BlueMap stores freeze state in
`<BLUEMAP_DATA>/pluginState.json`, where `<BLUEMAP_DATA>` is the path selected by
BlueMap's `core.data` setting, relative to the instance data directory. The
stock Setup backup allowlist covers plugin paths only and does not include this
state file. A deployment adopting freeze scheduling must preserve this one file
in its private backup and verifier, or re-freeze every map after restore and
before exposing the viewer. Do not put its contents in Git; it can include
private marker and freeze state.

## Spawn view after a world reset

Each generated map opens the viewer at its `start-pos`, which defaults to
`{ x: 0, z: 0 }` — usually unrendered void after a reset regenerates the world
with a new seed. `automation/bluemap-spawn-view.py` points each map at the fresh
overworld spawn and enforces the inhabited-time policy:

```bash
python3 automation/bluemap-spawn-view.py --check --server-dir /srv/minecraft/instances/<instance-data>
python3 automation/bluemap-spawn-view.py --apply --server-dir /srv/minecraft/instances/<instance-data>
```

It reads the overworld spawn from `world/level.dat` (gzip NBT; both the 1.21.2+
`Data.spawn.pos` int array and the legacy `Data.SpawnX`/`Data.SpawnZ` fields are
supported) and rewrites only the single `start-pos` line of `maps/world.conf` to
the overworld x/z and of `maps/world_the_nether.conf` to the floor-divided
`x/8`, `z/8` (the Nether coordinate mapping). The End map stays at
`{ x: 0, z: 0 }`. The same run enforces `min-inhabited-time` (default `1200`,
override with `--min-inhabited-time`) on all three maps.

`--check` reports the detected spawn and the pending edits without writing;
`--apply` rewrites each config atomically (temp file plus rename, mode and owner
preserved) and prints the `bluemap reload` reminder. It fails closed: an
unreadable or unrecognized `level.dat` leaves `start-pos` unchanged, and a
missing or ambiguous config line is never edited. BlueMap generates `maps/*.conf`
itself, so these values are not templated in this repo.

The guarded reset calls this automatically after every configured map
acknowledges its purge (so BlueMap is loaded) and then runs `bluemap reload`; a
failure warns only and never blocks the reset. See [world-reset.md](world-reset.md).

## Purge and re-render after a world reset

A world reset replaces the terrain, so purge each configured map and let BlueMap
rebuild it:

```text
/bluemap purge world
/bluemap purge world_the_nether
/bluemap purge world_the_end
```

`purge` deletes only BlueMap's generated output, not Minecraft world or region
files. It affects the map tiles only. An idle/updated status alone does **not**
prove the previous world's tiles were removed — explicitly purge after a reset
and allow a rebuild. The guarded reset script queues a purge for every configured
map and requires BlueMap's acknowledgment before it advances the seed index
(rendering itself continues in the background). See [world-reset.md](world-reset.md).

## Player positions, markers, and waypoints

Terrain batches do not batch the live player and marker layers. BlueMap's online
player positions, shared Compass waypoints, and offline-player markers continue
to be visible as those features update.

BlueMap Offline Player Markers is an upstream Paper plugin that adds a separate,
toggleable marker set for players at their last saved logout position. It shows
the player's name and last-seen time. Its defaults keep the marker set visible,
hide spectators and banned players, and do not expire old markers (`0` hours is
unlimited). Review these defaults and the
[upstream README](https://github.com/TechnicJelle/BlueMapOfflinePlayerMarkers)
before enabling it. Its upstream release describes Paper 1.13+ compatibility.
The 3.x release line added and fixed the newer Minecraft player-data layout; v3.3
includes a fix to skip zero UUID data. Verify the chosen release against your
exact Paper and BlueMap builds.

The addon reads Minecraft player-data files for the saved location and writes a
derived player-name cache in its own config directory. Minecraft world player
data is the source of truth for positions; if retaining addon configuration,
back up only `plugins/BlueMapOfflinePlayerMarkers/config.yml`. The name cache is
derived and need not be backed up. Treat world data, addon configuration, and map
output as private; do not commit player identities, positions, or server data.
The upstream plugin performs update checks and uses bStats usage telemetry.
Marker skins and fallback player-name resolution use BlueMap's configured skin
provider and may fall back to Mojang. Review the provider and metrics policies
for your deployment before enabling it.

Persistent POI markers are limited to administrator-managed static markers and
waypoints published by Awepeeps-BlueMap-Compass. A player sneak-right-clicks an
allowed block (default: lodestone or banner) with any compass to create or remove
a waypoint. Nothing teleports the player and no durability is used; the in-game
indicator is visible only while holding a compass.

BlueMap's built-in `/bluemap` commands do not create persistent markers. Offline
Player Markers adds display-only offline-player markers and no edit commands.
Do not add guessed permission denials — they would block nothing. If a separate
marker-command addon is introduced, verify its documented create/edit/delete
permission nodes and deny them to ordinary players while keeping admin access.

## Placeholders in exported marker metadata

Do not export marker metadata, player identities, or coordinates from this
private server into the public setup repository. The configured viewer may
intentionally show static POIs and player positions to its authorized audience;
that runtime map output remains private. Static markers should describe a
location, not a person.

## References

- [BlueMap core settings](https://bluemap.bluecolored.de/wiki/configs/Core.html)
- [BlueMap map settings](https://bluemap.bluecolored.de/wiki/configs/Maps.html)
- [BlueMap commands](https://bluemap.bluecolored.de/wiki/getting-started/Commands.html)
- [BlueMap markers](https://bluemap.bluecolored.de/wiki/customization/Markers.html)
- [BlueMap Offline Player Markers upstream releases](https://github.com/TechnicJelle/BlueMapOfflinePlayerMarkers/releases)
