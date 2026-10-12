# Bedrock access (Geyser + Floodgate)

Bedrock cross-play has two parts: **Geyser + Floodgate** on the server, and — on
a Windows/WSL2 host — getting **UDP 19132** from the LAN to the guest.

## 1. Server side

Install the `Geyser-Spigot` and `Floodgate-Spigot` jars into
`<instance-data>/plugins/`, then restart from the panel. Merge the key settings
from `config/plugins/Geyser/config.yml.template` and
`config/plugins/Floodgate/config.yml.template`:

- Geyser listens on UDP **19132** (default).
- Geyser connects to the Java server on localhost:25565.
- Geyser `auth-type: floodgate`; Floodgate links Bedrock players without a Java
  account.
- Bedrock players join at `<SERVER_HOST>`, port **19132** — no port override needed.
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
| 19132 | udp | Bedrock/Geyser (must be forwarded) |
| 23333, 24444 | tcp | MCSManager panel — **LAN only, never forwarded** |
| 8100 | tcp | BlueMap web map — LAN-only until a reverse proxy/TLS fronts it |

## 3. WSL2 NAT limitation

On Windows 10, WSL2 runs behind NAT and `netsh portproxy` handles TCP only, so
**inbound UDP 19132 from the LAN does not reach a server inside the WSL2 guest**.
There are two fixes:

- **Mirrored networking** (Windows 11 22H2 and later): enable it so the guest
  shares the host's network and the forwarded UDP port reaches it directly.
- **A UDP forwarder** on the Windows host: a small program that listens on
  `0.0.0.0:19132/udp`, relays datagrams to the guest's IP, and returns replies.

Caveats for the forwarder approach:

- The WSL guest IP changes on every reboot and host sleep; the forwarder must
  re-resolve it (for example from `wsl hostname -I`) periodically, and Bedrock
  sessions break across an IP change.
- A simple single-client forwarder is fine for a friends server with one active
  Bedrock player; many concurrent Bedrock clients need a real UDP NAT.

If you run the whole server on Linux (no WSL2), none of this applies: just
forward UDP 19132 to the host.

## 4. Consoles

Bedrock on Switch/PlayStation/Xbox needs the per-console workarounds documented
on the Geyser wiki ("Using Geyser with Consoles") — usually a DNS trick or a
connected LAN session. Follow that page per console; it changes more often than
this guide does.

## Test checklist

- [ ] Phone (mobile) joins via `<SERVER_HOST>` on port 19132.
- [ ] Bedrock chat appears to Java players.
- [ ] `/fwhitelist add <gamertag>` works.
- [ ] The forwarder/mirroring log shows UDP 19132 reaching the guest.
- [ ] The router forwards UDP 19132.
