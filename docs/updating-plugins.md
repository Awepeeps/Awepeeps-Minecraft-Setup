# Updating plugins

Plugin versions are pinned by exact version (or source commit) plus the SHA-256
of the jar. Never install a floating `latest`; never invent a hash — measure it.

## Third-party plugins (direct jars)

1. Find the new release and confirm it states support for your Paper version.
2. Download the exact jar and measure its digest:
   ```bash
   curl -fsSL -o /tmp/plugin.jar <RELEASE_JAR_URL>
   sha256sum /tmp/plugin.jar
   ```
3. Update the entry in `plugins/plugins.list`:
   `name|source|version|url|sha256` — version, URL and digest together.
4. Verify, then install:
   ```bash
   SERVER_DIR=/srv/minecraft/instances/<instance-data> DRY_RUN=1 \
     bash automation/install-plugins.sh
   SERVER_DIR=/srv/minecraft/instances/<instance-data> \
     bash automation/install-plugins.sh
   ```
   `install-plugins.sh` refuses a jar whose bytes do not match the pin, and
   rejects a URL that is not `https` (or `localhost` for the tests).
5. Keep both Via plugins (ViaVersion and ViaBackwards) at matching versions.
6. Restart from the panel and check the console for load errors and the reported
   version.

## Awepeeps plugins (built from a pinned source commit)

The group's own plugins live in public repos under the `Awepeeps` org. They are
built locally from a pinned commit, and the built jar's digest is recorded in the
manifest.

1. Merge the plugin change; note the merged commit (full 40-character SHA) and the
   source's version string.
2. Update the source pin:
   ```bash
   cp config/sources/chestcleaner.env.example config/sources/chestcleaner.env   # first time only
   # edit CHESTCLEANER_SOURCE_COMMIT and CHESTCLEANER_VERSION
   ```
   Same for `bluemap-compass.env` (`build-bluemap-compass.sh`) and
   `spawn-kit.env` (test-only, `build-spawn-kit.sh`).
3. Record the expected digest in the manifest, then build:
   ```bash
   bash automation/build-chestcleaner.sh
   ```
   The helper clones exactly that commit, runs the source repo's own build, and
   **fails** if the jar does not match the digest in `plugins/plugins.list`. A
   mismatch usually means the manifest digest still needs updating; update it to
   the measured value and re-run so the pin is self-consistent.
4. Copy the verified jar from `artifacts/` into
   `<instance-data>/plugins/` (the artifact name is `Name-version.jar`;
   ChestCleaner's plugin folder is `ChestCleaner`).
5. Restart from the panel and check the console.

A merged plugin PR alone does not change a running server. The chain is:

```
plugin PR merged → update the source pin + version → rebuild → update the manifest digest
→ verify → install the jar → restart → verify in game
```

Cold-start and reset jobs consume the pins, so update the pins before the next
scheduled run; nothing fetches a moving branch.

## Pins in the private deployment

Instance-specific pins and the live manifest live in the private deployment
repository. This public repo carries only the generic template and the format.
When you change a pin here, mirror the change into the deployment (or record it
there) so the running server and the template do not drift.

## Before and after any upgrade

- Take a manual backup first ([backups.md](backups.md)), even outside the schedule.
- Upgrade on a staging instance first, never during the backup window or right
  before peak play.
- After a Minecraft drop, re-check every plugin against the new version and
  re-apply any renamed `server.properties` or Paper config keys.
- Roll back by restoring yesterday's snapshot and pointing the version back.
