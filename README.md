# Awepeeps Minecraft Setup

A public, portable template for a whitelist-only Paper Minecraft server:
configuration templates, operating guides, and reusable automation. Follow
[`docs/bootstrap.md`](docs/bootstrap.md) on a clean machine to end up with a
working server running the group's plugin set (Java + Bedrock cross-play, a web
map, permissions, verified backups).

## The two-repository rule

This project is deliberately split in two:

- **`Awepeeps-Minecraft-Setup` (this repository) — public, generic, portable.**
  It is the template for a fresh server. It contains **no secrets, no personal
  data and no instance-specific values** — no real hostnames, IPs, ports that are
  not defaults, usernames, home-directory paths, MCSManager ids, player names or
  UUIDs, whitelist/ops contents, world seeds, coordinates, Discord ids, webhook
  URLs, tokens or passwords. Everything instance-specific is a placeholder such
  as `<SERVER_HOST>`, `/srv/minecraft`, or `CHANGE_ME`.
- **`Awepeeps-Minecraft-Deployment` — private, the real running instance.** The
  only place instance values and secrets may live.

Do not copy a file from the private deployment into this repository verbatim.
Read it line by line and replace every instance-specific value with a placeholder.
Never merge the private repository's history into this one.

## What you get

- Paper on Java 25 in the `itzg/minecraft-server` Docker image, managed through
  MCSManager (web panel + daemon).
- Whitelist-only: `white-list`, `enforce-whitelist`, `online-mode` all on, with
  owner-reviewed manual approval for new Java and Bedrock players.
- Bedrock cross-play via Geyser + Floodgate.
- ViaVersion + ViaBackwards, LuckPerms, EssentialsX Core (version pending Paper
  26.3 validation), BlueMap, Awepeeps-ChestCleaner, Awepeeps-BlueMap-Compass,
  and (test-only) Awepeeps-SpawnKit. FreedomChat is optional; if installed, its
  chat rewrite setting stays off.
- Plugins pinned by exact version or source commit **plus the SHA-256 of the jar**,
  and verified before install.
- Verified backups, a guarded disposable-test world reset, and a maintenance report.

## Quick start

```bash
git clone https://github.com/Awepeeps/Awepeeps-Minecraft-Setup.git /srv/minecraft/setup
cd /srv/minecraft/setup
cp .env.example .env            # fill in; .env is gitignored
docker compose up -d            # MCSManager panel
```

Then work through [`docs/bootstrap.md`](docs/bootstrap.md). Fill in
`plugins/plugins.list` (and the `config/sources/*.env` files) with real pins
before installing plugins, and never invent a version or hash — measure it.

## Repository map

| Path | Contents |
|---|---|
| `docs/` | Guides: bootstrap, whitelist, bedrock, nicknames and permissions, bluemap, backups, world-reset, updating-plugins, testing, maintenance, local-recovery |
| `config/` | Sanitized templates (`server.properties`, Paper defaults, plugin configs) and `config/sources/*.env.example` source pins |
| `plugins/` | The plugin list and manifest templates (`plugins.list`, `test-plugins.list`) and the release/pin model |
| `automation/` | Backup/verify/reset/report/build/install scripts and their mock tests |
| `seasons/` | Sanitized, per-server/season policy records |
| `compose.yaml` | MCSManager panel (web + daemon) |
| `.env.example` | Every documented variable with placeholder values |

## Testing

```bash
bash automation/run-tests.sh
```

This runs `bash -n`, the mock suites (backup, install-plugins, daily-reset,
maintenance, snapshot, season-end) without Docker or network, and is the same set
CI runs alongside `shellcheck`, YAML validation, and a secret scan.

## Contribution workflow

The org repository is canonical: `Awepeeps/Awepeeps-Minecraft-Setup`.
- `origin` is your personal fork; `upstream` is the org.
- Work on a branch, push to `origin`, and open a pull request against the org's
  `main`.
- The running instance is managed in the separate private deployment repository.
- The group's plugins are maintained in their own public repos under the
  `Awepeeps` org (see [`plugins/README.md`](plugins/README.md)).

Before every push, scan the whole tree for secrets and instance values (see the
CI secret scan and the checklist in [`docs/updating-plugins.md`](docs/updating-plugins.md)).

## Working in this repository

Repo-wide rules for agents are in [`AGENTS.md`](AGENTS.md). The sanitizing
port workflow — turning a private-deployment change into a portable template — is
in
[`.agents/skills/portable-template-change/SKILL.md`](.agents/skills/portable-template-change/SKILL.md).
