---
name: portable-template-change
description: Make or port a change to the public Awepeeps-Minecraft-Setup template so it stays portable and sanitized. Use when editing templates, scripts, docs, or plugin pins, or when importing work from the private deployment.
---

# Portable template change

This repository is public and generic. Every change must stay free of instance
values and secrets, and must reproduce on a clean host.

## Workflow

1. Confirm the change belongs here: a generic template, guide, automation
   script, or pin format. Instance-specific configuration and live pins belong
   in the private `Awepeeps-Minecraft-Deployment` repo.
2. If porting from the private deployment, edit file-by-file. Replace **every**
   instance value with a placeholder: `<SERVER_HOST>`, `<instance-data>`,
   `/srv/minecraft`, `CHANGE_ME`. Never copy a file verbatim and never merge
   private history (see [README.md](../../../README.md)).
3. For a plugin pin, measure the exact artifact: full version or 40-character
   commit, plus the SHA-256 of the built/downloaded jar. Never invent a version
   or hash; add a mock test when the pin path changes.
4. Where a value legitimately depends on the reader's Paper/plugin version, mark
   it `TODO` instead of guessing.
5. Keep the module docs in sync: `README.md`, `docs/README.md`,
   `config/README.md`, `plugins/README.md`, `automation/README.md`. A new
   automation script gets a row in `automation/README.md`, a `run` entry in
   `automation/run-tests.sh`, and a mock test beside it.

## Validate before pushing

```bash
bash automation/run-tests.sh   # mock suites, no Docker/network/live server
find . -name '*.sh' -not -path './.git/*' -print0 | xargs -0 -n1 bash -n
shellcheck --severity=warning --external-sources <changed scripts>
```

CI additionally validates YAML and runs a gitleaks secret scan. Then read your
own diff for any hostname, IP, path, username, id, seed, coordinate, or secret
that slipped through. When in doubt, treat the value as private.

## Boundaries

- Do not add `.cursor` rules or duplicate guidance; repo skills live under
  `.agents/skills/`.
- Do not weaken an automation's safety gate to make a test pass.
- Do not add instance-specific defaults, credentials, or production decisions.

See [AGENTS.md](../../../AGENTS.md) for repo-wide rules.
