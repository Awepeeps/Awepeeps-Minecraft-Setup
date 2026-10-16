# Bedrock access (Geyser + Floodgate)

Bedrock cross-play has two parts: **Geyser + Floodgate** on the server, and — on
a Windows/WSL2 host — getting the **Bedrock ports** from the LAN to the guest.

## 1. Server side

Install the `Geyser-Spigot` and `Floodgate-Spigot` jars into
`<instance-data>/plugins/`, then restart from the panel. Merge the key settings
from `config/plugins/Geyser/config.yml.template` and
`config/plugins/Floodgate/config.yml.template`:

- Geyser listens on UDP **19132** for RakNet and serves **NetherNet** alongside
  it; see [NetherNet](#5-nethernet-bedrock-2640-transport).
- Geyser connects to the Java server on localhost:25565.
- Geyser `auth-type: floodgate`; Floodgate links Bedrock players without a Java
  account.
- Bedrock players join at `<SERVER_HOST>`. Older clients use RakNet on port
  **19132** — no port override needed; Bedrock 26.40+ clients use NetherNet
  (TCP 19132 signaling, UDP 19133 media).
- Manage Bedrock players with `/fwhitelist` (see [whitelist.md](whitelist.md)).

Version interplay: Geyser emulates a Java client version. A server on a newer
Paper version accepts it because **ViaBackwards** is installed; newer Java
clients are covered by ViaVersion. Do not remove either Via plugin without
checking every client class. If Geyser's stable release fails to load on your
Paper version, **check for a stable release that supports your Paper version**;
the reference instance used a 2.12.0 preview build because stable 2.11.3 failed on
Paper 26.3.

Chat: Bedrock players do not carry a signed Java chat profile, so the server
keeps `enforce-secure-profile=false`. **Trade-off:** this relaxes signed-chat
enforcement for Java clients too; it does not weaken authentication or the
whitelist. If Bedrock players cannot chat, check Geyser's secure-chat guidance
and the server setting before anything else.

Quick cross-check from the server console:

```text
geyser connectiontest <client-ip> 19132
```

## 2. Ports and firewall

| Port | Protocol | Purpose |
|---|---|---|
| 25565 | tcp | Java players |
| 19132 | udp | Bedrock RakNet — older clients (must be forwarded) |
| 19132 | tcp | Bedrock NetherNet HTTP signaling (forward for Bedrock 26.40+) |
| 19133 | udp | Bedrock NetherNet media (forward for Bedrock 26.40+) |
| 23333, 24444 | tcp | MCSManager panel — **LAN only, never forwarded** |
| 8100 | tcp | BlueMap web map — LAN-only until a reverse proxy/TLS fronts it |

Allow inbound for the Bedrock ports on the server host: TCP 19132 (NetherNet
signaling), UDP 19132 (RakNet) and UDP 19133 (NetherNet media). On a Linux host:

```bash
sudo ufw allow 19132/udp   # RakNet
sudo ufw allow 19132/tcp   # NetherNet signaling
sudo ufw allow 19133/udp   # NetherNet media
```

On Windows/WSL2, add the matching inbound rules on the **Private** profile from
an elevated (Administrator) PowerShell — run these yourself; the guide does not
change host firewall rules for you:

```powershell
New-NetFirewallRule -DisplayName 'Minecraft Bedrock signaling (TCP 19132)' -Direction Inbound -Protocol TCP -LocalPort 19132 -Action Allow -Profile Private
New-NetFirewallRule -DisplayName 'Minecraft NetherNet (UDP 19133)' -Direction Inbound -Protocol UDP -LocalPort 19133 -Action Allow -Profile Private
```

Remember that a normal TLS/HTTP reverse proxy cannot carry the raw game TCP/UDP
traffic; public Bedrock access needs direct router forwards.

## 3. WSL2 NAT limitation

On Windows 10, WSL2 runs behind NAT and `netsh portproxy` handles TCP only, so
**inbound UDP 19132 and 19133 from the LAN do not reach a server inside the WSL2
guest**. TCP 19132 (NetherNet signaling) already forwards through the usual WSL
TCP proxy. There are two fixes for the UDP ports:

- **Mirrored networking** (Windows 11 22H2 and later): enable it so the guest
  shares the host's network and the forwarded UDP ports reach it directly.
- **A UDP forwarder** on the Windows host: a small program that listens on
  `0.0.0.0:19132/udp` (and `0.0.0.0:19133/udp`), relays datagrams to the guest's
  IP, and returns replies.

Caveats for the forwarder approach:

- The WSL guest IP changes on every reboot and host sleep; the forwarder must
  re-resolve it (for example from `wsl hostname -I`) periodically, and Bedrock
  sessions break across an IP change.
- A simple single-client forwarder is fine for a friends server with one active
  Bedrock player; many concurrent Bedrock clients need a real UDP NAT.

If you run the whole server on Linux (no WSL2), none of this applies: just
forward the Bedrock ports (UDP 19132, TCP 19132, UDP 19133) to the host.

## 4. Consoles

Bedrock on Switch/PlayStation/Xbox needs the per-console workarounds documented
on the Geyser wiki ("Using Geyser with Consoles") — usually a DNS trick or a
connected LAN session. Follow that page per console; it changes more often than
this guide does.

## 5. NetherNet (Bedrock 26.40+ transport)

Bedrock 26.60 (planned 2026-10-27) removes RakNet, so a current Geyser build
serves **NetherNet** alongside it. The keys are in
`config/plugins/Geyser/config.yml.template`; merge them into the generated
`<instance-data>/plugins/Geyser-Spigot/config.yml`.

- `bedrock.transport: both` — RakNet stays for older clients; NetherNet serves
  26.40+ clients. Use `raknet` to disable NetherNet, or `nethernet` once every
  client is on 26.40+.
- `bedrock.webrtc-port: 19133` — the single NetherNet media (WebRTC) port. Under
  `transport: both` it must differ from the RakNet port (`19132`) or NetherNet
  refuses to start.
- `bedrock.signaling.mode: builtin` — Geyser serves NetherNet's HTTP signaling
  itself on **TCP 19132**; `GET /v1/join` returns the server-info JSON.
- `bedrock.signaling.builtin.advertise-addresses` — **every** address players
  reach NetherNet on, suffixed with the media port (for example
  `<lan-ip>:19133`, `<tailnet-ip>:19133`, `<public-ip>:19133`). Never the
  container's internal address, and never just one candidate: a client handed an
  address it cannot reach fails to connect.

A NetherNet-capable Geyser build is required. Do **not** pin a preview build just
for NetherNet; choose a supported release for your Paper and Bedrock versions
(see [plugins.list](../plugins/plugins.list)).

Without HTTPS each Bedrock player sees a one-time "trust on first use" prompt
keyed to the operator key at `plugins/Geyser-Spigot/nethernet/identity.pem`.
Back that file up: losing it re-prompts every player. It is a private key, so
keep it out of Git (`.gitignore` covers `*.pem`); `automation/backup.sh` archives
it when the default `PLUGIN_DATA_PATHS` is unchanged.

With HTTPS signaling configured Geyser **rejects** plain-HTTP signaling, so
players must switch from raw addresses to the TLS hostname — a migration, not a
drop-in. HTTPS does not change the UDP media candidate. A normal TLS/HTTP reverse
proxy cannot carry the raw game TCP/UDP traffic anyway; public NetherNet access
needs direct router forwards.

Verify:

```bash
docker port <container>            # 19132/tcp, 19132/udp, 19133/udp, 25565/tcp
curl http://<host>:19132/v1/join   # server-info JSON
```

Geyser logs `Built-in signaling started on http://0.0.0.0:19132, with NetherNet
on UDP port 19133` when both transports start.

Rollback: restore `transport: raknet`, `webrtc-port: 0`, and an empty
`advertise-addresses`, then restart; the published ports and firewall rules can
stay inert.

## Test checklist

- [ ] Phone (mobile) joins via `<SERVER_HOST>` on port 19132.
- [ ] Bedrock chat appears to Java players.
- [ ] `/fwhitelist add <gamertag>` works.
- [ ] `docker port <container>` shows `19132/tcp` and `19133/udp`, Geyser logs
      its built-in signaling line, and `curl http://<host>:19132/v1/join`
      returns the server-info JSON (see
      [NetherNet](#5-nethernet-bedrock-2640-transport)).
- [ ] The forwarder/mirroring log shows UDP 19132 and 19133 reaching the guest.
- [ ] The router forwards UDP 19132 (and, for Bedrock 26.40+, TCP 19132 and
      UDP 19133).
