# Bootstrap: clean Linux host to a running server

This guide takes a clean Linux machine to a working, whitelist-only Paper server
with the group's plugin set. It is written for a capable hobbyist, not a
developer: every command is copy-pasteable, and each step says how to verify it
worked. A short WSL2 note is at the end.

Placeholders you must replace:

- `<SERVER_HOST>` — the hostname players use (never a raw IP in player-facing text).
- `<instance-data>` — the server's data directory name under the workspace root.
- `/srv/minecraft` — the reference server root; use any absolute path you own.

> The exact commands were validated against the reference deployment's templates
> and scripts. Where a value depends on your Paper/plugin version it is marked
> **TODO** rather than guessed.

## 0. What you will end up with

- Paper on Java 25, run by the `itzg/minecraft-server` Docker image.
- MCSManager (web panel + daemon) managing that container.
- Whitelist-only access (`white-list`, `enforce-whitelist`, `online-mode` all on).
- Owner-reviewed manual approval for new Java and Bedrock players.
- Bedrock cross-play through Geyser + Floodgate.
- EssentialsX Core for nicknames and moderation after its chosen release passes
  the exact Paper build check; use LuckPerms grants from
  [`nicknames-and-permissions.md`](nicknames-and-permissions.md) instead of
  operator access.
- The group's plugin set, pinned to exact versions/commits and verified by SHA-256.
- A web map (BlueMap) and a private, verified backup routine.

## 1. Prerequisites

- A Linux host (Ubuntu 24.04 or similar) with root/sudo. On Windows, use WSL2
  (see the note at the end); do **not** use Docker Desktop.
- Docker Engine and the Compose plugin.
- `git`, `curl`, `python3`, `flock`, GNU `timeout` and `tar`.
- Two directories you own:
  - a control checkout of this repository (config, automation, docs);
  - a data root for instance data and backups, kept outside the checkout.

## 2. Directory layout

Decide on a root and create the layout. Backups and instance data must live
outside the git checkout and outside each other.

```bash
sudo mkdir -p /srv/minecraft
sudo chown "$USER":"$USER" /srv/minecraft
mkdir -p /srv/minecraft/instances /srv/minecraft/backups
git clone https://github.com/Awepeeps/Awepeeps-Minecraft-Setup.git /srv/minecraft/setup
cd /srv/minecraft/setup
cp .env.example .env    # fill this in; .env is gitignored
```

Important paths:

| Path | Purpose |
|---|---|
| `/srv/minecraft/setup` | this repository (templates, scripts, docs) |
| `/srv/minecraft/instances/<instance-data>` | the managed server's data (mounts as `/data`) |
| `/srv/minecraft/backups` | private, owner-only backup storage |
| `/srv/minecraft/.reset-state` | lifecycle lock and reset state |

## 3. Install Docker (if not already present)

```bash
sudo apt update && sudo apt install -y ca-certificates curl gnupg
curl -fsSL https://get.docker.com | sudo sh
sudo usermod -aG docker "$USER"    # log out and back in
docker run --rm hello-world        # verify
```

## 4. Bring up MCSManager

From the checkout:

```bash
cd /srv/minecraft/setup
mkdir -p data
docker compose up -d
docker compose ps                  # both containers should be running
```

Open the panel at `http://<SERVER_HOST>:23333` (or the host's LAN address) and
set a strong administrator password on first login. **Keep ports 23333 and 24444
private** — LAN/VPN only, never forwarded from the router.

`MCSM_DOCKER_WORKSPACE_PATH` in `.env` must be an absolute host path and must
match the bind source in `compose.yaml`. MCSManager hands instance data paths to
the host Docker daemon, so a relative path is invalid.

## 5. Create the Minecraft instance

In the panel, create an instance (Docker process type). Set **Start Command
empty** — the image reads its configuration from environment variables.

Image and environment:

| Setting | Value |
|---|---|
| Image | `itzg/minecraft-server:java25` (explicit Java 25 tag) |
| `EULA` | `TRUE` |
| `TYPE` | `PAPER` |
| `VERSION` | your Paper Minecraft version, e.g. the current drop (**TODO**: confirm) |
| `ENABLE_WHITELIST` | `TRUE` |
| `ENFORCE_WHITELIST` | `TRUE` |
| `ONLINE_MODE` | `TRUE` |
| `ENABLE_RCON` | `TRUE` |
| `RCON_PASSWORD` | a strong secret, set only in the instance env |
| `SIMULATION_DISTANCE` | `8` (maps to `server.properties` `simulation-distance`; view distance stays `10`) |
| `INIT_MEMORY` / `MAX_MEMORY` | e.g. `1G` / `3G` (see below) |
| `MEMORY` | fallback that sets both heap bounds; keep e.g. `3G` |
| Container memory limit | e.g. 4096 MB (4 GiB) |

The itzg image defaults `ENABLE_WHITELIST` to **false**. Set
`ENABLE_WHITELIST=TRUE` **and** `ENFORCE_WHITELIST=TRUE`, and also keep
`white-list=true` + `enforce-whitelist=true` in `server.properties`; the
environment value writes the first-boot file, and the property is what keeps
the door locked on every later boot.

Heap: start at 1 GiB, grow to 3 GiB inside a 4 GiB container limit. The
remainder is headroom for metaspace, thread stacks and native memory. For this
image `MEMORY` sets both heap bounds; `INIT_MEMORY`/`MAX_MEMORY` set them
independently.

Simulation distance is `8` chunks while view distance stays `10`. Crops, mob
spawning and redstone only tick within simulation distance (~128 blocks at 8),
and BlueMap's inhabited-time filter counts every chunk within it, so the map
draws roughly a 128-block radius around where players spent time rather than the
~160-block view-distance radius. Lowering simulation distance reduces per-tick
work; raising it widens both the ticking area and the explored-terrain map. The
image maps `SIMULATION_DISTANCE` to the matching `server.properties` key on
start, so an edit takes effect on a container recreate, not a plain stop/start.
See [bluemap.md](bluemap.md).

Ports to publish on the instance:

| Port | Protocol | Purpose |
|---|---|---|
| 25565 | tcp | Java players |
| 19132 | udp | Bedrock RakNet — older clients (Geyser) |
| 19132 | tcp | Bedrock NetherNet HTTP signaling (Geyser, Bedrock 26.40+) |
| 19133 | udp | Bedrock NetherNet media (Geyser, Bedrock 26.40+) |
| 8100 | tcp | BlueMap web map (LAN-only until a reverse proxy/TLS is set up) |

Bedrock 26.40+ clients use NetherNet, which adds TCP 19132 and UDP 19133;
older clients keep using UDP 19132. See
[bedrock.md](bedrock.md#5-nethernet-bedrock-2640-transport).

## 6. First start

Start the instance and watch the console. On first boot the image generates
`server.properties`, the world, and the Paper config. Verify in the console:

```text
/list
```

Then stop the instance from the panel, apply the config templates (next steps),
and start it again.

Apply the server properties and Paper defaults from the templates:

- `config/server.properties.template` → `<instance-data>/server.properties`
  (merge the keys; the existing file may already hold the RCON secret),
- `config/paper-world-defaults.template.yml` → `<instance-data>/config/paper-world-defaults.yml`.

`enforce-secure-profile=false` is required for Bedrock players via Geyser, which
does not carry a signed Java chat profile. **Trade-off:** this relaxes signed-chat
enforcement for Java clients too. It does not weaken authentication or the
allowlist. Set it in `server.properties`.

## 7. Whitelist the first player

1. The player tries to connect and is rejected; the attempt appears in the console.
2. In the console:
   ```text
   whitelist add <exact-minecraft-name>
   ```
   UUIDs resolve automatically. (For a stubborn case, `whitelist add <uuid>` with
   a name-to-UUID lookup.)
3. Tell them to retry against `<SERVER_HOST>` (default port).

For a Bedrock player, after Geyser/Floodgate are installed:

```text
fwhitelist add <bedrock-gamertag>
```

`whitelist add` also works once Floodgate links the Bedrock identity, but
`fwhitelist` is the correct command. See [whitelist.md](whitelist.md).

## 8. Install the pinned plugins

1. Fill in `plugins/plugins.list` (and `plugins/test-plugins.list` for a test
   server): every version/commit and the SHA-256 of the exact jar bytes. Never
   invent a hash — measure it after a verified download or build.
2. Download and verify the third-party jars:
   ```bash
   SERVER_DIR=/srv/minecraft/instances/<instance-data> DRY_RUN=1 \
     bash automation/install-plugins.sh     # verify only
   SERVER_DIR=/srv/minecraft/instances/<instance-data> \
     bash automation/install-plugins.sh      # verify and install
   ```
3. Build the group's own plugins from their pinned source commits:
   ```bash
   cp config/sources/chestcleaner.env.example config/sources/chestcleaner.env   # fill in
   cp config/sources/bluemap-compass.env.example config/sources/bluemap-compass.env
   bash automation/build-chestcleaner.sh
   bash automation/build-bluemap-compass.sh
   ```
   Each helper refuses to produce an artifact that does not match the pin, and
   copies the verified jar to `artifacts/`. Copy those jars into
   `<instance-data>/plugins/` and record their SHA-256 in the manifest.
4. Install order, restarting the instance from the panel after each group:
   ViaVersion + ViaBackwards → LuckPerms → EssentialsX Core (after validating
   its supported stable release, or an exact official development build if no
   stable release supports this Paper version) → BlueMap →
   ChestCleaner → AwepeepsBlueMapCompass. Geyser + Floodgate come with the
   Bedrock step. FreedomChat is optional; see its template before installing.
5. Check the console after each boot for plugin load errors.

Geyser note: the stable 2.11.3 release fails on Paper 26.3. **Check for a stable
release that supports your Paper version**; prefer a stable release when one
supports your version. A preview build may be needed when no stable release does.

## 9. Apply plugin configs

Merge the templates in `config/plugins/` into the plugin files that are generated
on first boot (do not replace the whole file):

- BlueMap: `core.conf` (accept the download), `webapp.conf` (port `8100`, slider
  `0/160/160`, `max-zoom-distance: 512`), and each map file
  (`min-inhabited-time: 30`). See [bluemap.md](bluemap.md).
- ChestCleaner: `config.yml`, then run the one-time command checklist in
  `config/plugins/LuckPerms/README.md` and set the cleaning item in game with a
  brush and `/cleaningitem set`.
- AwepeepsBlueMapCompass: `config.yml` (lodestone/banner targets).
- Geyser + Floodgate: `config.yml` key settings. Once `transport` is `both` or
  `nethernet`, `bedrock.signaling.builtin.advertise-addresses` **must** list every
  address players reach NetherNet on (`host:19133`), never the container's
  internal address; an empty list only works when every player reaches the address
  Geyser bound. See [bedrock.md](bedrock.md).
- EssentialsX Core: review generated `config.yml` and apply the minimal LuckPerms
  grants documented in [nicknames-and-permissions.md](nicknames-and-permissions.md).
- FreedomChat (optional): merge `config/plugins/FreedomChat/config.yml.template`
  and confirm the selected version supports `rewrite-chat: false`. With chat
  rewriting disabled, this plugin does not make outgoing messages unreportable;
  treat it only as a compatibility option, not a privacy or moderation control.
- Overhead nicknames: deferred. Current community nameplate candidates do not
  have a verified Paper 26.3 release with confirmed Geyser/Floodgate behavior.
  EssentialsX nicknames in chat and tab remain independent of this decision.
- AwepeepsSpawnKit: **test servers only.** Keep the live-safe template disabled; a
  disposable test server may use `preseason.example.yml`. See
  [world-reset.md](world-reset.md).

## 10. Verify

- [ ] Java client connects with the whitelisted account; a non-whitelisted name is rejected.
- [ ] `/viaversion`, `/lp info`, `/bluemap` (or `/bluemap`) respond without errors.
- [ ] EssentialsX Core loads at the exact tested version; the default group has
      no new EssentialsX grants unless the owner deliberately enables self-nick,
      and has no moderation/admin grants.
- [ ] FreedomChat, if installed, loads and its generated config has
      `rewrite-chat: false` and `claim-secure-chat-enforced: false`.
- [ ] Console shows every pinned plugin loaded at the expected version.
- [ ] BlueMap responds at `http://<host>:8100/` after a render.
- [ ] Bedrock join works (see [bedrock.md](bedrock.md)), and for Bedrock 26.40+
      `docker port <container>` shows `19132/tcp` and `19133/udp` with
      `curl http://<host>:19132/v1/join` returning the server-info JSON.
- [ ] `bedrock.signaling.builtin.advertise-addresses` lists every address your
      players use (each as `host:19133`) and never the container's internal
      address; it may stay empty only if every player reaches Geyser's bound
      address.
- [ ] `automation/backup.sh` produces a verified archive and `automation/backup-verify.sh` accepts it.

## 11. Not ready for the internet until

- [ ] `white-list=true` and `enforce-whitelist=true` are present in `server.properties`.
- [ ] The container env sets `ENABLE_WHITELIST=TRUE` and `ENFORCE_WHITELIST=TRUE`.
- [ ] `online-mode=true`; no offline-mode workaround is in place.
- [ ] The RCON password and every other secret are set outside Git (`.env`, secret
      manager, or the instance env), never committed.
- [ ] Panel ports 23333/24444 are LAN/VPN only and not forwarded.
- [ ] At least one backup has been produced, verified, and test-restored.
- [ ] The whitelist flow, the Bedrock flow, and a rejected-join are all rehearsed.
- [ ] `automation` scripts run under systemd user units with explicit environment;
      the schedules are in your timezone.

## WSL2 note

If the host is Windows with WSL2: run everything above **inside** the distro
(with systemd enabled and `dockerd` running in the distro, not Docker Desktop).
One limitation matters: on Windows 10, WSL2 uses NAT networking and Windows'
`netsh portproxy` is TCP-only, so **inbound UDP 19132 and 19133 from the LAN
cannot reach the guest**. Fix it with one of:

- **Mirrored networking** (Windows 11 22H2+): enables LAN access to the guest
  directly; or
- a **UDP forwarder** on the Windows host that relays 19132 and 19133 into the
  WSL guest.

TCP 25565 and TCP 19132 already forward to the guest through the usual WSL TCP
proxy. See [bedrock.md](bedrock.md) for details and the caveat that the guest IP
changes on reboot.
