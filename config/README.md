# Configuration templates

Sanitized templates for a fresh Paper server. Every value here is a generic
placeholder or a safe default; instance-specific values (hostnames, paths,
player lists, seeds, secrets) belong in the private deployment and in ignored
local files, never here.

Each template's header states where the file goes on the server. Replace
`<instance-data>` with the server's data directory (the Docker bind-mount source
that becomes `/data` inside the container).

| Template | Destination on the server |
|---|---|
| `server.properties.template` | `<instance-data>/server.properties` |
| `paper-world-defaults.template.yml` | `<instance-data>/config/paper-world-defaults.yml` |
| `plugins/ChestCleaner/config.yml` | `<instance-data>/plugins/ChestCleaner/config.yml` |
| `plugins/AwepeepsSpawnKit/config.yml` | `<instance-data>/plugins/AwepeepsSpawnKit/config.yml` |
| `plugins/AwepeepsSpawnKit/preseason.example.yml` | test-only; see the file header |
| `plugins/AwepeepsBlueMapCompass/config.yml` | `<instance-data>/plugins/AwepeepsBlueMapCompass/config.yml` |
| `plugins/BlueMap/core.conf.template` | `<instance-data>/plugins/BlueMap/core.conf` |
| `plugins/BlueMap/webapp.conf.template` | `<instance-data>/plugins/BlueMap/webapp.conf` |
| `plugins/BlueMap/maps/example.conf.template` | `<instance-data>/plugins/BlueMap/maps/<map-id>.conf` |
| `plugins/Geyser/config.yml.template` | `<instance-data>/plugins/Geyser-Spigot/config.yml` |
| `plugins/Floodgate/config.yml.template` | `<instance-data>/plugins/floodgate/config.yml` |
| `plugins/LuckPerms/README.md` | no file template; command-based basics |
| `plugins/EssentialsX/config.yml.template` | `<instance-data>/plugins/Essentials/config.yml` |
| `plugins/FreedomChat/config.yml.template` | `<instance-data>/plugins/FreedomChat/config.yml` |

`plugins/AwepeepsWhitelistGate/config.yml.template` is retained only as a
recovery reference for older installations. The plugin is retired from the
recommended setup; follow [manual whitelist approval](../docs/whitelist.md).

`config/sources/*.env.example` documents the source pins used by
`automation/build-*.sh`. Copy an example to the matching `.env` and fill it in;
the real file is gitignored.

## Applying templates

Most plugins generate their configuration file on first boot. Stop the server,
merge the values from the template into the generated file (do not replace the
whole file), and start again. `server.properties` and `paper-world-defaults.yml`
are the exception: apply them before the first boot where noted.
