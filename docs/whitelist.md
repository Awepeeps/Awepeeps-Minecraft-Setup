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
`fwhitelist` is the correct command. They join `<SERVER_HOST>`, UDP port 19132.
See [bedrock.md](bedrock.md).

## Removing a player

```text
whitelist remove <name>
fwhitelist remove <name>     # Bedrock
```

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
