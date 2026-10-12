# Guides

Portable setup, upgrade, backup, and operations guides. Use examples and
placeholders instead of live deployment details.

- [Bootstrap](bootstrap.md): clean Linux host (and a WSL2 note) to a running,
  whitelist-only Paper server with the plugin set.
- [Whitelist management](whitelist.md): allowlist policy, Java and Bedrock
  onboarding, and the Discord approval flow (webhook is a secret).
- [Bedrock access](bedrock.md): Geyser/Floodgate, UDP 19132, and the WSL2 NAT
  limitation with its two fixes.
- [BlueMap](bluemap.md): viewer settings, explored-terrain policy, purge
  behavior, and marker policy.
- [Backups and restore](backups.md): live-safe backups, verification, retention,
  scheduling, restore, and the local status report.
- [Guarded test-world reset](world-reset.md): the self-expiring disposable-world
  reset and its safety gates.
- [Updating plugins](updating-plugins.md): from a merged plugin change to an
  updated pin and an installed, verified jar.

Policy and background:

- [Agent-assisted Minecraft testing](testing.md): public workflow, safety gates,
  verified compatibility scope, acceptance checklist, and teardown steps.
- [Maintenance](maintenance.md): portable backup, reset, restore-verification,
  retention, and map-maintenance policy.
- [Local recovery and privacy](local-recovery.md): WSL startup, managed recovery,
  safe configuration history, local failure reports and dynamic spawn markers.
