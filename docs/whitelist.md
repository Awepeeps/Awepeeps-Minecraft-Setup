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

## Awepeeps Whitelist Gate (Discord approval flow)

Awepeeps-Whitelist-Gate watches for join attempts from players who are not on the
whitelist and notifies the owner in Discord. The owner approves from the console.
It is an addition to the allowlist, never a replacement: the server stays
`enforce-whitelist=true` whether or not the plugin is running.

- The plugin reads its webhook URL from the environment variable
  `WLGATE_DISCORD_WEBHOOK_URL`. **That URL is a secret.** It belongs in the
  private deployment's `.env` or a secret manager, and must never appear in Git,
  in a config file that could be shared, or in logs and screenshots.
- Because it is supplied as an environment variable, set it on the Docker
  instance (the panel's instance environment), not in `config.yml`.
- Approving a player is a console action, run by the owner. Players cannot
  approve themselves.
- The plugin repository is private and in progress. Follow its own README for the
  exact approval command; the config template in `config/plugins/AwepeepsWhitelistGate/`
  lists what is and is not confirmed (**TODO**).

## Rules of thumb

- Never op a friend to "make something work" — grant the minimal plugin
  permission instead.
- Whitelist names and UUIDs are player identity data. Never export them to Git.
  Keep them only in private, access-controlled server backups.
- Rehearse the reject-then-approve flow on the disposable test server before you
  rely on it on the live server.
