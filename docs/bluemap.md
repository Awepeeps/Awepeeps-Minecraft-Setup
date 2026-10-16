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

Set `min-inhabited-time: 30` in each map configuration
(`plugins/BlueMap/maps/<map-id>.conf`, for example `world`,
`world_the_nether`, `world_the_end`). At 20 game ticks per second, this is an
approximate threshold of 1.5 seconds of cumulative chunk inhabited time. Leave
any inhabited-time radius at its default zero.

This is a **map-render threshold**, not an exact record of what a client saw:
nearby time can qualify a chunk, while client visibility and render timing are
separate. Changing it requires a map re-render. Minecraft's `view-distance` is
independent. See the
[official map configuration reference](https://bluemap.bluecolored.de/wiki/configs/Maps.html).

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

## Markers and waypoints

Two kinds of markers:

- **Administrator-managed** static markers, configured by hand and kept out of
  player control.
- **Waypoints** published by Awepeeps-BlueMap-Compass. A player sneak-right-clicks
  an allowed block (default: lodestone or banner) with any compass to create or
  remove a waypoint. Nothing teleports the player and no durability is used; the
  in-game indicator is visible only while holding a compass.

BlueMap's built-in `/bluemap` commands do not create persistent markers, and the
installed plugin set has **no marker-command addon**. Do not add guessed
permission denials — they would block nothing. If a marker-command addon is later
introduced, verify its documented create/edit/delete permission nodes and deny
them to ordinary players while keeping admin access.

## Placeholders in exported marker metadata

Keep coordinates and player identities out of any exported marker metadata.
Static marker sets should describe a location, not a person. Player positions
are a separate live display feature.

## References

- [BlueMap map settings](https://bluemap.bluecolored.de/wiki/configs/Maps.html)
- [BlueMap commands](https://bluemap.bluecolored.de/wiki/getting-started/Commands.html)
- [BlueMap markers](https://bluemap.bluecolored.de/wiki/customization/Markers.html)
