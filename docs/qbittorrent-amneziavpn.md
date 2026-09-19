# QBittorrent with amnezia vpn microvm

- use microvm.nix https://github.com/microvm-nix/microvm.nix
- inside vm enable amnezia vpn (use unstable package)
- inside vm enable qbittorrent nox
- port forward webui port to host
- do not port forward other ports

- amnezia vpn client requires gui to login and configure: therefore, provide vnc over ssh setup and sway

- vm has 2 cpu cores and 2GiB RAM

## Implementation

- Host module: `hosts/nas/qbittorrent-amneziavpn.nix`; guest module:
  `hosts/nas/qbittorrent-amneziavpn-guest.nix`.
- Declarative microvm.nix QEMU guest, autostarted by
  `microvm@qbittorrent-amneziavpn.service`. Two vCPUs, **2049 MiB** RAM:
  upstream warns that QEMU can hang at exactly 2048 MiB.
- Private TAP `qbt-tap`: host `10.76.0.1/30`, guest `10.76.0.2/30`.
  Host NAT supplies outbound connectivity. No bridged LAN access or incoming
  torrent-port forwards. Guest interface naming is pinned to `eth0`.
- Only NAS TCP 8080 is published, via systemd-socket-proxyd to guest TCP 8080.
  WebUI: `http://nas:8080` (trusted networks only; HTTP, not TLS).
  The previous container's Traefik labels no longer apply.
- Headless Sway starts automatically as `vpn`, running unstable AmneziaVPN and
  wayvnc bound to **guest loopback only**. SSH uses `constants.main-pub-keys`,
  with password authentication disabled. The `vpn` operator has passwordless
  sudo inside the guest.
- Persistent 8 GiB root image:
  `/var/lib/microvms/qbittorrent-amneziavpn/state.img`. Contains VPN credentials,
  desktop state, SSH host keys and qBittorrent profile. Keep it private; back up
  with the VM stopped. It is outside the existing `/srv` backup.
- Read-only host store share; writable download shares:
  `/mnt/hdd/torrent → /downloads`,
  `/home/ilma4/torrents → /ssd-downloads`.
  qBittorrent UID/GID 1000 matches the old container's file ownership.
- Guest nftables blocks qBittorrent's UID from physical-interface egress,
  except established WebUI responses to the host proxy. Tunnel traffic remains
  allowed. IPv6 is disabled. No local DNS proxy is used: systemd-resolved is
  forcibly disabled so DNS requests cannot escape through another UID.
  Use a tunnel-based Amnezia profile with full routing, not a local SOCKS proxy.
  Set a reachable VPN DNS server if the profile requires one.

## First start and migration

The NAS import replaces the old container and its IP polling watchdog. Its
module, configuration, encrypted WireGuard secret and download data are retained
for rollback; no secret is deleted or copied into the Nix store. Do not run both
clients on the same torrents simultaneously.

After explicitly deploying the configuration:

1. Open an SSH tunnel (no guest SSH/VNC ports are published on NAS):
   `ssh -J ilma4@nas vpn@10.76.0.2 -N -L 5900:127.0.0.1:5900`.
2. Connect a VNC viewer to `127.0.0.1:5900`. Import/login to AmneziaVPN,
   connect, and enable automatic connection. Credentials remain inside the image.
3. Obtain the initial WebUI password from the guest:
   `ssh -J ilma4@nas vpn@10.76.0.2 sudo journalctl -u qbittorrent`.
   Log in as `admin` at `http://nas:8080`, set a permanent password and set
   the default download path to `/downloads` or `/ssd-downloads`.
   Bind qBittorrent to the actual VPN interface in Advanced settings as a second
   safeguard. Do not disable WebUI authentication.
4. Existing torrent session/config migration is manual: stop qBittorrent in the
   guest before copying the old profile into
   `/var/lib/qBittorrent/qBittorrent`, preserving UID/GID 1000. Check the guest's
   `systemctl cat qbittorrent` for the profile location before copying.
   Existing downloads need not be moved.

## Validation

- Run `./utils/flake-check.sh` before deployment.
- On NAS check `systemctl status microvm@qbittorrent-amneziavpn`.
- In the guest check `systemctl --user status vpn-desktop`,
  `sudo systemctl status AmneziaVPN qbittorrent`, and
  `sudo nft list table inet qbt-killswitch`.
- Before adding real torrents: confirm the VPN public IP using a torrent IP
  test, disconnect the VPN, confirm torrent/DNS traffic stops while WebUI
  remains accessible, then reconnect. Repeat after a guest reboot.
- Verify NAS publishes no new SSH, VNC or torrent ports, only TCP 8080.
  Evaluation checks do not substitute for these runtime tests.
