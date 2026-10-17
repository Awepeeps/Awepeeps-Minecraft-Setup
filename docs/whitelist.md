# Whitelist management

The server is allowlist-only, permanently. Keep `white-list=true` and
`enforce-whitelist=true` in `server.properties`, and keep the itzg container
environment `ENABLE_WHITELIST=TRUE` and `ENFORCE_WHITELIST=TRUE`. Operators are
added deliberately and are not the same thing as whitelisted players.

## Adding a Java player

1. They try to connect with `<SERVER_HOST>` and are rejected; the attempt shows
   in the console and logs.
2. In the server console (in the panel):
   ```text
   whitelist add <exact-minecraft-name>
   ```
   UUIDs resolve automatically. If a name is ambiguous or stuck, add the UUID
   directly: `whitelist add <uuid>`.
3. Tell them to retry against `<SERVER_HOST>` (default port).

## Adding a Bedrock player (Geyser + Floodgate)

Bedrock players have no Java account. With Floodgate installed:

```text
fwhitelist add <bedrock-gamertag>
```

`whitelist add` also works once Floodgate links the Bedrock identity, but
`fwhitelist` is the correct command. They join `<SERVER_HOST>`; older clients use
UDP 19132 (RakNet) and Bedrock 26.40+ clients use NetherNet. See
[bedrock.md](bedrock.md).

If the gamertag lookup fails with **"Unable to find user in our cache"**, add the
player by XUID instead. The GeyserMC global API only knows players it has already
seen, while a Floodgate UUID is derived from the XUID alone. Look up the player's
decimal XUID, write it as 16 hex digits, and add the Floodgate UUID
`00000000-0000-0000-XXXX-XXXXXXXXXXXX` where `XXXX-XXXXXXXXXXXX` are those 16
hex digits:

```text
fwhitelist add 00000000-0000-0000-XXXX-XXXXXXXXXXXX
```

`whitelist add <uuid>` accepts the same UUID once Floodgate has linked the
identity. Convert the decimal XUID to hex carefully (a calculator or a lookup
site that shows the XUID is fine); do not guess the digits.

## Removing a player

```text
whitelist remove <name>
fwhitelist remove <name>     # Bedrock
```

## Verify enforcement

Keep `white-list=true` and `enforce-whitelist=true`. The itzg image can rewrite
`server.properties` from its environment on a fresh instance or a container
recreate, silently turning the whitelist off. `automation/whitelist-check.sh` is a
read-only check that reads the mounted `server.properties` and fails (exit `1`)
when either whitelist property is not true, and exits `2` on bad input:

```bash
SERVER_DIR=/srv/minecraft/instances/<instance-data> bash automation/whitelist-check.sh
ONLINE_MODE_REQUIRED=1 SERVER_DIR=/srv/minecraft/instances/<instance-data> \
  bash automation/whitelist-check.sh    # also fail if online-mode is not true
```

`automation/daily-reset.sh` runs it against the reopened server and refuses to
advance the seed if the whitelist is off. `automation/maintenance-report.sh`
includes the same check when `SERVER_DIR` is set. The check only reads the file;
it never adds or removes players.

## Manual approval is the default

The rejected join attempt is the request. Review the exact Java name or Bedrock
gamertag with the player, then add it from the server console using the commands
above. Do not add a player until the owner has approved the request. The server
remains allowlist-only before and after approval; no separate approval service or
chat account link is required.

The legacy Awepeeps Whitelist Gate template is retained only for recovery of
older installations. It is retired from the recommended setup and is not needed
for manual approval.

## Rules of thumb

- Never op a friend to "make something work" — grant the minimal plugin
  permission instead.
- Whitelist names and UUIDs are player identity data. Never export them to Git.
  Keep them only in private, access-controlled server backups.
- Rehearse the reject-then-approve flow on the disposable test server before you
  rely on it on the live server.
