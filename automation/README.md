# Automation

Reusable setup, maintenance, backup, and verification tools. Every script reads
its configuration from the environment (see `../.env.example`) and has safe
defaults except where a value must be instance-specific (for example
`SERVER_DIR`). No script contains a hostname, IP, personal path, player name, or
individual instance id.

Every script is checked with `bash -n` and `shellcheck`, and the mock suites run
without Docker, network, or a live server.

## Scripts

| Script | Purpose |
|---|---|
| `backup.sh` | Live-safe backup: verifies the mount, locks, `save-off`/flush, archives the world plus allowlisted plugin data (Essentials config/per-player userdata, Geyser config and NetherNet identity key), validates, publishes atomically, rotates 7 daily / 4 weekly. |
| `backup-verify.sh` | Offline integrity, allowlisted plugin-path safety, and extraction check of one archive (or the newest). |
| `backup-scheduled.sh` | Phase gate around `backup.sh`: runs only in the active test/live phase, otherwise no-ops before touching Docker or storage. |
| `install-plugins.sh` | Downloads a manifest's pinned jars, verifies each SHA-256, and copies them into `plugins/`. Skips placeholders and non-jar (source-built) entries. |
| `build-chestcleaner.sh` | Builds Awepeeps-ChestCleaner from its pinned commit and verifies the jar against the manifest. |
| `build-bluemap-compass.sh` | Builds Awepeeps-BlueMap-Compass from its pinned commit and verifies the jar. |
| `build-spawn-kit.sh` | Builds Awepeeps-SpawnKit (test-only) from its pinned commit and verifies the jar. |
| `daily-reset.sh` | Guarded, self-expiring disposable-test world reset under the lifecycle lock. See `../docs/world-reset.md`. |
| `bluemap-spawn-view.py` | Points each BlueMap map at the fresh world spawn and enforces the inhabited-time policy after a reset (`--check` reports, `--apply` edits atomically). Reads `world/level.dat` (gzip NBT) and fails closed. See `../docs/bluemap.md`. |
| `whitelist-check.sh` | Read-only verify that the mounted `server.properties` still enforces `white-list`/`enforce-whitelist`. Fails closed (exit 1 when off, 2 on bad input). See `../docs/whitelist.md`. |
| `mcsm-start.js` | Reopens a saved MCSManager instance through the panel's own lifecycle API (used by the reset). Never prints config values. |
| `recovery-gate.sh` | Toggles the marker that stops an automatic boot-recovery job from reopening an intentionally stopped server. |
| `maintenance-report.sh` / `maintenance-status.py` | Local, read-only health summary: backup privacy/coverage and systemd unit results. Never sends anything. |
| `snapshot-policy.py` / `snapshot-to-git.sh` | Generates a sanitized, validated `policy.json` (allowlisted booleans/integers/enums only). Never stages, commits or pushes. |
| `season-end.sh` | Final verified backup + sanitized policy + permanent private archive + season README stamp. |
| `seeds.txt` | Curated seeds for the guarded reset (one literal integer per line; empty = random). |

Configuration source pins live in `../config/sources/*.env` (copy from the
`.env.example` files).

## Tests

Run everything (Docker/network not required):

```bash
bash automation/run-tests.sh
```

- `test-backup.sh` — backup, verify, retention and phase-gate mocks.
- `test-install-plugins.sh` — a local HTTP stub serves fixture jars; checks
  install, dry-run, digest mismatch, placeholder skip, `STRICT`, non-https
  rejection and unsafe names.
- `test-daily-reset.sh` — reset safety gates: expiry, pre-wipe backup, lock,
  symlink/hardlink refusal, seed rotation, Spawn Kit preloading, BlueMap purge
  acknowledgment, the warn-only spawn-view step, whitelist enforcement, and
  MCSManager reopen.
- `test-whitelist-check.sh` — whitelist enforcement: true/false/missing/empty,
  case and CRLF handling, last-occurrence wins, `ONLINE_MODE_REQUIRED`, and
  symlink/protected-path refusal.
- `test-maintenance-status.py`, `test-snapshot-policy.py`, `test-season-end.py`.
- `test-bluemap-spawn-view.py` — BlueMap spawn-view NBT layouts, line edits, and
  fail-closed apply.

## Not ported (lives in the private deployment)

The following were deliberately left in the private deployment repository
because they are entangled with one host's panel internals and network:

- **Cold-start / reboot recovery** (`recover-minecraft.sh` and its
  `recover-mcsm-host.js` / `recover-mcsm-preflight.js` helpers). It validates the
  saved MCSManager instance schema, reopens the instance through the panel, and
  rewrites the panel's saved node address when a WSL2 guest IP changes. The node
  address refresh and WSL-specific `ip`/panel-restart logic are specific to that
  host layout. This repo keeps the generic pieces it depends on
  (`mcsm-start.js`, `recovery-gate.sh`) and documents the behavior here. A Linux
  host without WSL2 does not need the IP refresh at all.
- **The private Mineflayer test harness** and its owner-protection / whitelist
  denial checks. Public workflow and safety gates are described in
  `../docs/testing.md`; the implementation is private.
- **The Windows UDP relay** for Bedrock on WSL2. The limitation and the two fixes
  are described in `../docs/bedrock.md`; the forwarder itself is host-specific.
- **The Windows firewall installer** (`install-minecraft-firewall.ps1`; six named
  rules plus `-Uninstall`). This template ships no firewall script on purpose: the
  inbound rules are documented generically for `ufw` (Linux host) and as manual
  `New-NetFirewallRule` commands (Windows/WSL2 host) in `../docs/bedrock.md`.
  Revisit only if a specific installer becomes necessary.

If you need one of these, port it from the private deployment the same way these
scripts were: replace every path, hostname, identifier and name with an
environment variable and a safe default, then add a mock test.
