# Local recovery and privacy

Finish local startup, maintenance and gameplay acceptance before exposing game
ports or enabling Bedrock. Keep management-panel ports private.

## Windows and WSL startup

WSL systemd starts when the distribution starts. Systemd services and user
lingering do not keep WSL alive, so arrange an explicit Windows logon task with
a long-running foreground WSL process. A logon task requires a user to log in;
it does not promise unattended recovery before logon. Verify Docker is enabled
inside the distribution and the panel containers have appropriate restart policies.
See [Microsoft's WSL systemd documentation](https://learn.microsoft.com/windows/wsl/systemd/).

Keep management-panel automatic restart disabled when it would race a scheduled
world reset. Reopen managed Minecraft instances through the panel lifecycle,
under the same exclusive lock used by backups and resets. Validate the exact
data mount, bound startup and RCON checks, and fail closed on mismatches. An
intentional-stop gate should prevent a boot-recovery service from reopening an
instance the administrator wants stopped. Recovery must never invoke a world wipe.

Use stable internal Docker DNS for panel-to-daemon automation. Discover the
current guest IP for browser/LAN access after a WSL restart. A browser node
endpoint or reverse proxy configured with the previous address needs attention;
never replace it by printing or publishing the full credential-bearing node config.

Test both an already-running no-op and a clean managed stop/reopen. Then perform
a planned Windows reboot with the operator and verify Docker, panel, Minecraft,
timers and current-address access. A mock or service restart cannot prove actual
Windows reboot recovery.

## Safe configuration history

Private repositories still must exclude credentials and player identities. Never
copy raw `server.properties`, access lists, plugin databases, worlds, logs or
authentication caches into Git. Keep restore material in private backups outside
the repository. Generate Git policy history from an explicit allowlist of validated
boolean, numeric and enum settings; exclude unknown keys and free text. Review
the generated diff before staging, and scan staged files plus history for secrets.

Report backup freshness, distinct-day/week coverage, failed maintenance services
and inactive timers locally. Document how operators read those reports. New
deployments accumulate retention coverage over time; a successful backup alone
does not prove seven days of history or successful restoration. External messages
and offsite transfers require a chosen private destination and authorization.

## Spawn marker lifecycle

Derive an administrator-managed spawn marker from the world's current spawn,
in a separate map layer from player waypoints. Update it after world replacement,
spawn changes and map reload; disabling it should remove only that owned layer.
Avoid seed-specific coordinates and player identities in exported marker metadata.

For disposable tests, an opt-in supply chest can make acceptance easier. Require
an explicit expiry date and timezone, default it off, and derive its location
from current spawn. Place it only above a solid floor in empty space, mark its
ownership, and preserve existing contents across restart. Never overwrite player
blocks or ordinary chests. Expiry disables future placement; it must not erase
player items. Keep the setting disabled in the live-season configuration.
