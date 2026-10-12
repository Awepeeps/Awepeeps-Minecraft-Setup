# Maintenance policy

This guide defines portable operational safeguards for an instance-specific
deployment. It is policy, not an implementation or a report that a deployment
has been accepted. The private deployment repository owns schedules, server
versions, configuration, and automation. Keep those details out of this public
repository. The public setup guide describes the generic server scaffold;
deployment operation and the separately maintained BlueMap Compass source have their
own boundaries.

## Service priority and lifecycle coordination

Prioritize the local Minecraft server and its local-player experience. Run and
verify local server work before optional external Bedrock connectivity checks.
An external Bedrock service or test must not take precedence over local service
availability or recovery.

All jobs that can stop, replace, copy, restore, or otherwise mutate the server
must coordinate through one shared lifecycle lock. This includes reset, backup,
restore, upgrades, and any scheduled test. A job must acquire the lock before
it inspects or changes lifecycle state, and must release it on every exit path.
If the lock cannot be acquired, the job must stop without changing the instance.

## Daily reset and backup gates

Use the instance's configured Eastern time zone, including daylight-saving
transitions, for the daily schedule:

- At **03:45**, take an early backup for the daily test/reset window. It must
  complete and pass its configured integrity checks before the test begins.
- At **04:00**, the test-world reset first takes its own verified pre-wipe
  backup. A missing, failed, incomplete, or unverifiable backup is a hard
  precondition failure: stop the run and do not wipe or reset anything.
- At **05:45**, take the daily live-season backup once the configured cutover
  date has arrived. Before that date this job does nothing. Date gates switch
  the backup schedule and expire the test wipe; they do not perform a world
  cutover, restore, or season launch automatically.

During a disposable-world rehearsal, run the installed backup and reset services
with explicit authorization to wipe that sandbox. Verify a fresh world seed,
preserved whitelist/operators and plugin settings, reset POIs, and post-start
game rules. Verify the pre-wipe archive separately in an isolated restore.
Check BlueMap output as well: an idle or updated status alone does not prove the
previous world's terrain tiles were removed. The reset should request a purge
for every configured map, check its acknowledgment, and let BlueMap rebuild.

The exact date, server version, and automation settings belong in private
deployment configuration. Do not copy instance-specific values into this guide.

## Backup contents, handling, and retention

Store backups in owner-controlled private storage, outside any public source
repository. Create files and directories with permissions restrictive to the
owner (for example, a `umask` of `077` where supported). Backups can contain
credentials and other secrets through server properties or plugin data; treat
the entire archive as secret-bearing. Never publish snapshots, backup listings
with identifying metadata, or restore artifacts.

A complete snapshot must consistently capture the world data and all relevant
dimensions, POI data, and server properties. Quiesce or use a storage-consistent
snapshot method so the files belong to one coherent point in time. Keep the
manifest and integrity information with the private backup, not in this repo.

Retention policy:

- Keep the latest usable backup for each of the most recent **seven distinct
  calendar days**.
- Also keep **four weekly Sunday points** as longer-range recovery points.
- A weekly point may coincide with a daily point; do not delete a required daily
  point just to force four additional files. Apply retention only after checking
  that the required calendar coverage still exists. If available backups cannot
  satisfy the policy, report the gap and retain what exists rather than pruning
  further.

## Restore verification

Verify backups offline in an isolated disposable environment before relying on
them for recovery. Restore with the exact server and plugin versions recorded
for that snapshot, using private configuration. Keep the environment isolated:
publish no network ports, attach no active production data mounts, and prevent
the restored instance from reaching or being reached by the live service. Boot
the restored server and inspect startup and world-load results without exposing
it to players.

Cleanup is mandatory after verification: stop the isolated server, remove its
temporary containers or processes, mounts, scratch files, and restored copy, and
confirm that no test instance or temporary port remains. Record pass/fail and
the tested backup identity privately. This public policy does not assert that a
particular backup or deployment has passed verification.

## BlueMap explored-area behavior

BlueMap's `min-inhabited-time` filters rendered chunks using cumulative player
time near a chunk. A value of **30 ticks** is approximately **1.5 seconds** at
20 ticks per second. It is a map-render threshold, not an exact record of what a
client has seen: nearby time can qualify a chunk, while client visibility and
render timing are separate. Adjusting this setting requires a map rerender.
Purging and rerendering BlueMap affects map tiles only; it does not change
Minecraft's world generation, chunk state, or server view distance. See the
[official BlueMap map configuration reference](https://bluemap.bluecolored.de/wiki/configs/Maps.html)
for `min-inhabited-time` and rerender behavior.

## Shared marker policy

Allow administrator-managed spawn markers and the shared waypoint layer
published by Awepeeps-BlueMap-Compass. Players sneak-right-click a permitted
lodestone or banner with a compass to create or remove a waypoint. Keep marker
targets administrator-controlled; in-game item requirements do not hide the
shared map layer. Vanilla lodestone compass binding alone does not register a
waypoint.

BlueMap's current built-in commands do not provide persistent marker creation.
Keep server configuration administrator-controlled and omit marker-command addons.
If an addon is introduced, review its documented create/edit/delete permissions
before enabling it for players. Audit existing static marker sets and legacy POIs:
older imported records may predate lodestone-only creation. Live player positions
are a separate display feature from these persistent POIs. See
[BlueMap commands](https://bluemap.bluecolored.de/wiki/getting-started/Commands.html)
and [marker configuration](https://bluemap.bluecolored.de/wiki/customization/Markers.html).
