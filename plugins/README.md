# Plugins

The plugin set for the server. Pins, URLs and SHA-256 digests live in
`plugins.list` (live-safe) and `test-plugins.list` (test-only). The group's own
plugins are maintained in their own public repositories under the `Awepeeps` org;
this repo records the pins and how to build and verify them, and never contains
plugin runtime data or built binaries.

EssentialsX Core is planned, but its version must be confirmed on the exact Paper
build before enabling the manifest entry. TAB is not a replacement for the
vanilla overhead player name; overhead nickname rendering is deferred until a
community plugin has a verified Paper 26.3 release and Bedrock behavior.

## Third-party plugins

| Plugin | Purpose | Test-only |
|---|---|---|
| [ViaVersion](https://github.com/ViaVersion/ViaVersion) | Lets newer Java clients join an older server. | No |
| [ViaBackwards](https://github.com/ViaVersion/ViaBackwards) | Lets older Java clients (including Geyser's emulation) join a newer server. Keep matching ViaVersion. | No |
| [LuckPerms](https://luckperms.net/) | Permissions. Grants the minimal permission instead of opping friends. | No |
| [EssentialsX Core](https://github.com/EssentialsX/Essentials) | Nicknames, moderation commands, and core utilities. **Planned:** validate the chosen stable release on the exact Paper build before pinning. Use [`nicknames-and-permissions.md`](../docs/nicknames-and-permissions.md) for the permission policy. | No |
| [FreedomChat](https://github.com/ocelotpotpie/FreedomChat) | Optional chat compatibility layer. If used, set `rewrite-chat: false`; outgoing signed chat remains reportable. It is not a chat-report protection feature. | Optional; no default pin |
| [BlueMap](https://bluemap.bluecolored.de/) | Web map. | No |
| [Geyser](https://geysermc.org/) | Translates Bedrock clients to Java. Check for a stable release that supports your Paper version. | No |
| [Floodgate](https://geysermc.org/) | Lets Bedrock players in without a Java account. | No |

## Awepeeps plugins

| Plugin | Repository | Purpose | Test-only |
|---|---|---|---|
| Awepeeps ChestCleaner | [Awepeeps-ChestCleaner](https://github.com/Awepeeps/Awepeeps-ChestCleaner) | Maintained fork of ChestCleaner: brush-driven container and inventory sorting with server-set defaults. | No |
| Awepeeps BlueMap Compass | [Awepeeps-BlueMap-Compass](https://github.com/Awepeeps/Awepeeps-BlueMap-Compass) | Waypoints/compass integration with BlueMap (lodestone/banner markers, no teleport). | No |
| Awepeeps Spawn Kit | [Awepeeps-SpawnKit](https://github.com/Awepeeps/Awepeeps-SpawnKit) | Starter house + supply chest, a protected spawn pad, and a BlueMap spawn marker. | **Yes — test only** |

Reference versions on the live set: BlueMap Compass `1.4.1-awepeeps.8`,
ChestCleaner `2.4.5-awepeeps.1`. Spawn Kit's current reference pin is `1.1.3`
with a `1.2.0` redesign in progress upstream, and it is never added to the live
set. No plugin version is self-updating: the manifest pins an exact version (or
commit) and the jar digest.

**Retired:** the older `Navigator` plugin is no longer current. Its roles were
split into Awepeeps-SpawnKit (spawn features) and Awepeeps-BlueMap-Compass
(navigation/waypoints). Do not pin or install it.

## How the group's own plugins are released and pinned

1. The plugin is developed, tested and merged in its own public repo. Each
   release notes the merged commit and version.
2. The consuming server pins the **full 40-character commit** and the **version
   string** in `config/sources/<plugin>.env` (see the `.env.example` files), and
   pins the **SHA-256 of the built jar** in `plugins/plugins.list`.
3. `automation/build-<plugin>.sh` clones exactly that commit, runs the source
   repo's own build, and refuses to emit an artifact whose digest does not match
   the manifest. Verified jars land in `artifacts/` (gitignored).
4. The verified jar is copied into the server's `plugins/` directory and the
   server is restarted from the panel.
The former Awepeeps Whitelist Gate is retired from the recommended setup. Its
old config template remains only as a recovery reference for older installations.
New players are approved manually through the console; see
[`whitelist.md`](../docs/whitelist.md).

See [updating plugins](../docs/updating-plugins.md) for the full change flow.
