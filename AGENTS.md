# AGENTS.md — Awepeeps-Minecraft-Setup

Scope: **every file in this repository** (repo-wide). This is the public,
portable setup template. The private running instance lives in
`Awepeeps-Minecraft-Deployment`.

## What this repo is

Portable templates, operating guides, and reusable automation for a
whitelist-only Paper + Bedrock server. Start at [README.md](README.md) and
[docs/bootstrap.md](docs/bootstrap.md).

## Layout

- `docs/` — guides: bootstrap, whitelist, bedrock, bluemap, backups,
  world-reset, updating-plugins, testing, maintenance, local-recovery.
- `config/` — sanitized templates and `config/sources/*.env.example` source pins.
- `plugins/` — `plugins.list` / `test-plugins.list` pin format and release model.
- `automation/` — backup/verify/reset/report/build/install scripts (including
  the read-only `whitelist-check.sh` enforcement check and the BlueMap
  `bluemap-spawn-view.py` helper) and their mock tests.
- `seasons/` — sanitized, per-server/season policy records.
- `compose.yaml`, `.env.example` — MCSManager panel and documented variables.

## Privacy (public repo)

- Never commit secrets or instance values: hostnames, IPs, non-default ports,
  usernames, home paths, MCSManager ids/UUIDs, player names/UUIDs, whitelist/ops
  contents, seeds, coordinates, Discord ids, webhook URLs, tokens, passwords.
- Use placeholders such as `<SERVER_HOST>`, `<instance-data>`,
  `/srv/minecraft`, and `CHANGE_ME`.
- Never copy a file from the private deployment verbatim, and never merge its
  history. Replace each instance value, then scan the diff before pushing.

## Native-first default

MCSManager owns the container lifecycle; the itzg/Paper image owns the runtime.
Reuse the built-in environment, panel API, and plugin functions. Keep custom code
only for a documented gap (exact SHA-256 pins, backup verify/retention, shared
lifecycle lock, date cutoff, guarded reset, recovery). The deployment's map of
native vs. custom behavior is the reference for that split.

## Build / test

```bash
bash automation/run-tests.sh   # mock suites: no Docker, network, or live server
```

CI also runs `bash -n`, shellcheck, YAML validation, and a gitleaks secret scan.
Any shell, config, or doc change must keep `run-tests.sh` and CI green.

## Workflow

Read
[.agents/skills/portable-template-change/SKILL.md](.agents/skills/portable-template-change/SKILL.md)
for the sanitizing-port workflow. `origin` is your fork; `upstream` is the org.
PRs target `Awepeeps/Awepeeps-Minecraft-Setup`, and history never crosses into a
private repo.
