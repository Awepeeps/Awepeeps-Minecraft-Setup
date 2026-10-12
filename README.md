# Awepeeps Minecraft Setup

A scaffold for a repeatable Minecraft server blueprint, with portable
configuration templates and operating guides.

Deployment details and server data live outside this repository.

## Planned stack

- Paper for Minecraft Java Edition
- Geyser and Floodgate for Bedrock cross-play
- Docker and a server management panel
- Permissions, inventory sorting, compass navigation, and a web map
- Seasonal configuration, backups, and a disposable test environment

## Layout

| Directory | Intended contents |
|---|---|
| `config/` | Portable configuration templates with placeholders |
| `automation/` | Reusable setup, maintenance, and backup tools |
| `plugins/` | Custom plugin repository references |
| `docs/` | Setup and operations guides |
| `seasons/` | Sanitized season templates and release notes |

## Testing and repository boundaries

See [the testing guide](docs/testing.md) for the portable workflow and safety
checks used for agent-assisted Minecraft testing. It documents the public setup
scaffold and its relationship to the private deployment and plugin repositories.
See the [maintenance guide](docs/maintenance.md) for portable backup, daily
reset, restore-verification, and map-maintenance policy.

- **Awepeeps-Minecraft-Setup (this repository):** public, portable templates,
  documentation, and reusable setup materials.
- **Private deployment repository:** instance-specific pins, live configuration,
  and the guarded Mineflayer test harness. Do not publish these materials here.
- **Awepeeps-BlueMap-Compass:** public source code and tests for custom compass
  navigation, released separately.
- **Awepeeps-SpawnKit:** public generic one-time kit plugin; each consumer
  supplies its own contents and optional date window.

## Before importing implementation

Import selected files into this fresh history after reviewing them. Do not merge
deployment-repository history into this repository.

Replace addresses, hostnames, usernames, filesystem paths, player identifiers,
instance identifiers, and secrets with placeholders. Exclude live configs, worlds,
logs, screenshots, backups, generated artifacts, and access lists. Keep credentials
in local ignored files or a secret manager. Review staged changes and the Git
history before every publication.

This scaffold contains no working deployment and no production server information.

## Contribution workflow

The org repository is canonical: `Awepeeps/Awepeeps-Minecraft-Setup`.
Work in `deathpie/Awepeeps-Minecraft-Setup`, using `origin` for the personal fork
and `upstream` for the org. Submit pull requests against the org's `main` branch.
The actual running instance is managed in a separate private deployment repository.
Custom compass navigation is maintained separately in
`Awepeeps/Awepeeps-BlueMap-Compass`. Generic spawn kits are maintained
separately in `Awepeeps/Awepeeps-SpawnKit`.
