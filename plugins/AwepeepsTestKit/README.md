# Awepeeps Test Kit

Paper plugin for disposable test worlds. When explicitly enabled with a valid
inclusive expiry date and timezone, it places one shared, one-time starter
chest near the primary Overworld spawn. It waits for already-loaded terrain and
only uses a bounded, safe surface outside spawn protection. Existing blocks,
chests, and player builds are never replaced.

The plugin default is fail-closed (`enabled: false`, empty expiry and timezone).
Enable it only in a disposable test-server configuration. Keep it disabled and
out of the live-season plugin list. Disabling or expiring the feature prevents
new placement but does not remove an existing chest or reclaim distributed
items; resolve those explicitly during a separately authorized cutover.

Test configuration must supply a real expiry date and timezone, for example:

```yaml
test-supplies:
  enabled: true
  expires-on: "YYYY-MM-DD"
  timezone: "America/New_York"
```

Replace the date placeholder with the last day the test chest may be issued.
An invalid or missing date/timezone disables placement.

The kit is shared, not instanced per player. It contains lodestones, a bed,
compasses, a brush, basic building materials, banners, an anvil, a diamond
weapon/tool/armor set, torches, and 99 cooked beef. The complete kit fits in a
single chest.

The plugin stores an issuance tombstone per world UUID and an ownership marker
on its chest. Restarting does not refill a depleted chest or replace a removed
one. A successful disposable-world reset must clear
`plugins/AwepeepsTestKit/test-supplies.yml` only after all world directories
have been deleted; keep this file in the pre-wipe backup. This lets a fresh
world receive one kit even if the server reuses a world UUID.

## Build and tests

Requires JDK 25. From this directory run:

```sh
bash ./gradlew clean test build
```

The jar is written to `build/libs/awepeeps-test-kit-1.0.0.jar`.

## KitChests evaluation

[Cramber25/KitChests](https://github.com/Cramber25/KitChests) provides
per-player virtual kits from an administrator-converted container, but does
not place a kit after each daily world reset or provide a test/live expiry
gate. Its current source also clears the source container after attempting to
save the kit, even if persistence failed. It is therefore not adopted for
automated starter supplies. It may still be evaluated separately in an isolated
test world if per-player instanced rewards become a requirement.
