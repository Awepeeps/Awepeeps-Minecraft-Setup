# Plugin inventory and decisions

This is the public decision log for the portable template's recommended plugin
stack. It describes why each plugin is selected, what it changes, and whether
the template has enough evidence to call it validated. It is not an inventory
of any one running server. A deployment can make a different version-specific
choice and must keep its exact pins and instance state private.

The [live-safe manifest](../plugins/plugins.list) and
[test-only manifest](../plugins/test-plugins.list) are the source of truth for
template pin state. A TODO row is deliberately inactive until its version,
immutable download/source, and measured jar SHA-256 are filled in and reviewed.
The [configuration index](../config/README.md) maps sanitized settings
templates. This page records selection decisions; it does not duplicate pins.

## Recommended baseline

“Selected” means the role is part of the current stack decision. “Template
pending” means the public manifest does not yet contain a usable exact pin.
“Staging evidence” refers to a private deployment test and does not establish
that another operator's Paper build, plugin versions, or client mix is
compatible. See [server settings](server-settings.md) for native behavior and
the relationship between configuration layers.

| Plugin | Role and behavior change | Decision and evidence | Public source of truth |
|---|---|---|---|
| ViaVersion + ViaBackwards | Allows supported Java client versions on either side of the server protocol version. ViaBackwards is also needed for Geyser's emulated Java version when it is older. | Selected as a matched pair. Check the exact pair against the target Paper build before use; template pins are TODO. | [Manifest](../plugins/plugins.list) |
| LuckPerms | Supplies permission groups and node-level grants. It replaces the need to grant operator access for ordinary commands. | Selected; retain minimal grants and do not op friends. | [LuckPerms notes](../config/plugins/LuckPerms/README.md), [permissions guide](nicknames-and-permissions.md) |
| EssentialsX Core | Nicknames, moderation commands, and core utilities. It also contains economy features, which remain unused unless separately chosen. | Selected; an exact-pinned official development build passed isolated and staging startup checks on Paper 26.3. This is scoped startup evidence, not completed Java/Bedrock feature acceptance. Prefer a supported stable release; public artifact pins remain TODO and must be validated for each target. | [Template config](../config/plugins/EssentialsX/config.yml.template), [permissions guide](nicknames-and-permissions.md) |
| BlueMap | Renders a browser map from world chunks. Its configured explored-terrain policy limits map output, with limitations described in the feature guide. | Selected; exact pin remains a template placeholder and compatibility is target-specific. | [BlueMap guide](bluemap.md), [templates](../config/README.md) |
| Geyser + Floodgate | Geyser translates Bedrock connections to Java protocol; Floodgate authenticates Bedrock identities without a Java account. | Selected for Bedrock cross-play. Keep `online-mode` enabled. Verify a supported Geyser build and the full connection path for the target server. | [Bedrock guide](bedrock.md), [templates](../config/README.md) |
| Awepeeps ChestCleaner | Sneak-right-clicking a storage block with the brush sorts it directly; normal right-click still opens it. Sneak-right-clicking air sorts the player's own inventory. | Selected; exact source commit and jar digest are per deployment until portable pins are measured. | [Manifest](../plugins/plugins.list), [template config](../config/plugins/ChestCleaner/config.yml) |
| Awepeeps BlueMap Compass | With any compass, sneak-right-clicking a lodestone or banner creates/removes a waypoint; sneak-right-clicking air opens the waypoint menu. It does not teleport. The template sets `max-waypoint-distance: 50`. | Selected as the current navigation feature. Above-head player-name formatting is unrelated and still deferred. | [Manifest](../plugins/plugins.list), [template config](../config/plugins/AwepeepsBlueMapCompass/config.yml) |
| Awepeeps Spawn Kit | Adds a starter house, supplies, a protected spawn pad, and a map marker in disposable test worlds. | Test-only; never copy its pin into the live-safe list. | [Test-only manifest](../plugins/test-plugins.list), [config](../config/plugins/AwepeepsSpawnKit/config.yml) |
| Paper native allowlist | Restricts joins to owner-approved Java and Bedrock identities; approval remains a manual console action. | Selected; native feature is sufficient for this small manual workflow. It is a server feature, not a plugin. | [Whitelist guide](whitelist.md), [server properties](../config/server.properties.template) |

Do not use version strings shown in a manifest as proof that a matching jar is
installed or compatible. The public template may show reference versions beside
TODO source URLs or hashes; each server records its measured exact artifacts in
its own control checkout. Update the manifest and this page when a decision
changes, and record supporting tests in the relevant guide without adding
private pins here.

## Optional, deferred, and not selected

| Candidate | Decision | Reason and revisit condition |
|---|---|---|
| FreedomChat | Optional and used in the reference staging stack; its public manifest pin remains unfilled. | It may be chosen as a chat compatibility layer. It is not a chat-report protection feature. Its settings are release-specific; validate the generated config and distinguish `rewrite-chat` from the separate `claim-secure-chat-enforced` setting. The public template's `claim-secure-chat-enforced: false` is a template choice, not a claim about a private instance. Keep any staging pin private; revisit the public pin when a portable exact artifact is measured and reviewed. |
| Vault | Not selected / unnecessary for the current stack. | EssentialsX Core can run without it for the selected features. Revisit only if a chosen plugin has a required Vault integration. |
| EssentialsXChat, EssentialsXSpawn, EssentialsXDiscord | Not selected. | No current requirement needs these add-on modules. Revisit each separately if the server adopts its corresponding chat, spawn, or Discord feature. |
| DiscordSRV | Deferred. | Discord account synchronization and chat were optional homelab ideas; voice was dropped. Revisit only if a specific text-chat or account-linking requirement returns. No voice-chat plugin is selected. |
| TAB | Not selected for overhead names. | It can format the tab list but cannot replace the vanilla overhead player name. Revisit for tab-list presentation only, or if a separate requirement is validated. |
| UnlimitedNametags | Deferred / unverified. | Compatibility with the target Paper 26.3 line and the Geyser/Bedrock client path is not established. Review its current release, maintenance, dependencies (including PacketEvents and PlaceholderAPI where required), and Java/Bedrock behavior before considering it. |
| AdvancedWhitelist | Not selected. | Paper's native whitelist and manual owner approval cover the current workflow. Revisit if an actual approval workflow requirement appears that native commands cannot meet. |
| CoreProtect | Not selected / not needed for the current scope. | No current audit or rollback requirement. Revisit only if a new audit or rollback need appears. |
| WorldGuard, GriefPrevention, WorldEdit, Chunky, Spark, PlaceholderAPI, and other suggested additions | Unevaluated; not selected. | Suggestions were not reviewed deeply enough to call them rejected or compatible. For each, first define a concrete need, then review maintenance, permissions, data/backup impact, Paper and Bedrock behavior, and test evidence. |

Bedrock waypoint visuals are tracked externally in the plugin's own issue tracker,
[Awepeeps-BlueMap-Compass issue #5](https://github.com/Awepeeps/Awepeeps-BlueMap-Compass/issues/5).
That issue, not this page, carries the detail; it is not a plugin-selection TODO and
does not gate the current stack.

## Retired plugins

- **Awepeeps Whitelist Gate** is retired. Native Paper whitelist commands now
  handle manual approval. Its old template is retained only as a recovery
  reference for existing installations; do not install it in a new setup.
- **Awepeeps Navigator** is retired. The current navigation role is handled by
  Awepeeps BlueMap Compass; test-world spawn features belong to Spawn Kit. Do
  not pin or install Navigator.

## Keeping this record current

When a plugin is added, removed, promoted from test-only, or changed in purpose,
update this inventory and the appropriate manifest/config index in the same
change. State the reason and the condition that would cause the decision to be
revisited. Treat tests as scoped evidence: name the tested Paper/plugin/client
combination in a public guide only when it is safe and reproducible to publish;
never copy private deployment values or claim broader support than was tested.
