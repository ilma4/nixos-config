# qBittorrent with AmneziaWG in a microVM

The NAS runs qBittorrent directly in a dedicated microvm.nix QEMU guest with
AmneziaWG CLI tools. There is no AmneziaVPN GUI, Sway desktop or VNC server.

- Host module: `hosts/nas/qbittorrent-amneziavpn.nix`; guest module:
  `hosts/nas/qbittorrent-amneziavpn-guest.nix`.
- Two vCPUs, **2049 MiB** RAM: upstream warns that QEMU can hang at exactly
  2048 MiB.
- Private TAP `qbt-tap`: host `10.76.0.1/30`, guest `10.76.0.2/30` on `eth0`.
  Host NAT supplies IPv4 connectivity. The guest uses static addressing and no
  DHCP. IPv6 is enabled for VPN profiles that include `::/0`; the ordinary
  uplink remains IPv4 only.
- NAS relays guest TCP 8080 through systemd-socket-proxyd.
  WebUI: `https://qbittorrent.ilma4.home.arpa`, routed by Traefik through the
  host proxy at `10.20.0.1:8080`. Pi-hole's existing wildcard DNS points the
  hostname to NAS. Port 8080 accepts only Traefik's fixed `10.20.0.2` source
  address and host loopback; clients use HTTPS. No guest SSH or torrent ports
  are published.
- SSH user `vpn` uses `constants.main-pub-keys`, with password authentication
  disabled and passwordless sudo inside the guest.
- Persistent 8 GiB root image:
  `/var/lib/microvms/qbittorrent-amneziavpn/state.img`. It contains VPN keys,
  SSH host keys and the qBittorrent profile. Keep it private and back it up with
  the VM stopped. It is outside the existing `/srv` backup.
- Read-only host store share; writable download shares:
  `/mnt/hdd/torrent → /downloads`,
  `/mnt/ssd/torrent → /ssd-downloads` (the default download location).
  The ADATA NVMe is automounted at `/mnt/ssd` with Btrfs `compress=zstd:3`
  and xxHash checksums. The VirtioFS service requires the SSD mount, preventing
  downloads from falling back onto the NAS root filesystem if it is unavailable.
  qBittorrent UID/GID 1000 preserves existing download ownership.

## VPN and permanent firewall

`networking.wg-quick.interfaces.awg0` starts AmneziaWG automatically using
`/var/lib/amnezia/awg0.conf`. The tools and kernel module come from the existing
unstable pin: tools **3.1.20260812**, module **3.1.20260828** at this revision.
The stable pin's older versions do not support the current Premium exports.
Amnezia Premium currently exports
[AmneziaWG 3.1 profiles](https://docs.amnezia.org/documentation/instructions/personal_dashboard/#configuration-files).

The guest's nftables output policy drops traffic from **every user** unless it
is loopback traffic, traffic through `awg0`, UDP to the profile's exact VPN
endpoint, or established SSH/WebUI replies to `10.76.0.1`. Replies must belong to
connections initiated by the host. There is no general established-connection
exception, direct DNS exception, DHCP exception or forwarding allowance.
The same default-drop policy covers IPv4 and IPv6.

`qbittorrent-vpn-endpoint.py` reads only the profile's numeric IPv4 endpoint into
an nftables set at firewall start/reload. Missing or invalid profiles produce an
empty set, preserving SSH/WebUI access while blocking Internet access. Tunnel
startup validates the endpoint and reloads the firewall before connecting, so
changing the profile does not require duplicating the endpoint in Nix. Keys and
the subscription key stay outside the Nix store.

Networking and qBittorrent require successful firewall startup. Stopping the
firewall service retains its rules; reloads replace them atomically. The
restriction is independent of whether `wg-quick-awg0` starts or stops.
qBittorrent is also bound to `awg0` at each service start; this merges the
interface settings into its writable profile, preserving its password and other
WebUI settings. WebUI requests from `192.168.1.0/24` bypass authentication;
other client networks require a password. qBittorrent trusts forwarded client
addresses only from the host relay (`10.76.0.1`). The NAS firewall limits that
relay to Traefik and host loopback, preventing external clients from supplying
forged forwarding headers directly. `systemd-resolved` is disabled;
`awg-quick` applies the profile's DNS setting through resolvconf.

## Provisioning and migration

Deploy only when explicitly requested. Then export an **AmneziaWG `.conf`**
profile from your provider or the Amnezia client. A `vpn://` subscription string
or an Amnezia application backup is not an `awg-quick` configuration.

Prepare the profile locally:

- Use exactly one `Endpoint = numeric.IPv4.address:port`. Hostnames require DNS
  before the tunnel exists and are rejected.
- Keep the peer's `AllowedIPs = 0.0.0.0/0, ::/0` and automatic full-tunnel
  routing (no `Table = off`). Keep any provider-supplied IPv6 address in
  `Address`; IPv6 Internet access requires the provider to assign one.
- Keep the exported keys and AmneziaWG obfuscation parameters. Set `DNS` to an
  IPv4 resolver reachable through the tunnel, preferably the provider's resolver.

Copy the profile into the guest without adding it to this repository:

```sh
scp -o ProxyJump=ilma4@nas ./client.conf vpn@10.76.0.2:awg0.conf
ssh -J ilma4@nas vpn@10.76.0.2
```

Inside the guest:

```sh
sudo install -d -m 700 /var/lib/amnezia
sudo install -o root -g root -m 600 ./awg0.conf /var/lib/amnezia/awg0.conf
rm ./awg0.conf
sudo systemctl restart wg-quick-awg0
sudo systemctl restart qbittorrent
sudo journalctl -u qbittorrent
```

Open `https://qbittorrent.ilma4.home.arpa` from `192.168.1.0/24` for passwordless
access. Other networks log in as `admin` using the password from the journal.
Set a permanent password for those clients and choose `/downloads` or
`/ssd-downloads`. Advanced → Network interface should show `awg0`. The LAN
bypass and trusted proxy settings are reapplied at each qBittorrent start.
Restart `wg-quick-awg0` whenever replacing
the profile; restarting the firewall alone does not reconfigure the tunnel.

The previous container module, encrypted WireGuard secret and download data
remain available for rollback; no secret is deleted or placed in the Nix store.
Do not run both torrent clients on the same torrents simultaneously. Before
copying an old qBittorrent profile, stop qBittorrent and check its profile path
with `systemctl cat qbittorrent` (currently
`/var/lib/qBittorrent/qBittorrent/config/qBittorrent.conf`). Preserve UID/GID 1000.
The next start reapplies the `awg0` binding.

## Validation

Run `./utils/flake-check.sh` and
`python3 tests/qbittorrent-vpn-endpoint.py` before deployment. Flake checks
evaluate the configuration; the guest must also be built on Linux to run the
nftables rules checker, including its runtime-include fixture. After deployment,
check `systemctl status microvm@qbittorrent-amneziavpn` on NAS.

Inside the guest, before adding torrents:

```sh
sudo systemctl status nftables wg-quick-awg0 qbittorrent
sudo nft list table inet qbt-killswitch
sudo awg show
curl -4 --max-time 10 https://api.ipify.org
curl -6 --max-time 10 https://api6.ipify.org
```

Check the WebUI using a fresh browser session or a cookie-free request to
`https://qbittorrent.ilma4.home.arpa/api/v2/app/version`: LAN clients should get
HTTP 200 without logging in; clients outside `192.168.1.0/24` should get HTTP 403,
including requests with a forged `X-Forwarded-For` header. Direct NAS port 8080
should be inaccessible to those clients; only Traefik and host loopback may
reach the relay.

Confirm a recent handshake and the VPN public IP. The IPv6 request requires a
provider-assigned IPv6 address in the profile; a profile with only an IPv4
`Address` can install `::/0` but does not provide IPv6 Internet connectivity.
Then stop the tunnel:

```sh
sudo systemctl stop wg-quick-awg0
curl -4 --max-time 10 https://api.ipify.org
curl -4 --max-time 10 http://1.1.1.1
curl -4 --interface eth0 --max-time 10 http://1.1.1.1
curl -g -6 --max-time 10 'http://[2606:4700:4700::1111]'
```

All four requests must fail, including DNS-independent access. SSH and the
NAS WebUI must remain accessible, and existing torrents must lose connectivity.
Also reload and stop the firewall while the tunnel is down and confirm that
external requests remain blocked;
`sudo nft list table inet qbt-killswitch` must still show the rules. Stopping
nftables also stops its dependent services. Restore them afterward:

```sh
sudo systemctl start nftables systemd-networkd wg-quick-awg0 qbittorrent
```

Test a boot where the VPN never starts by temporarily removing its profile:

```sh
sudo mv /var/lib/amnezia/awg0.conf /var/lib/amnezia/awg0.conf.disabled
sudo reboot
```

Reconnect, repeat the failure and management-access checks above, and verify
that `awg0` is absent. Restore the profile and start the tunnel:

```sh
sudo mv /var/lib/amnezia/awg0.conf.disabled /var/lib/amnezia/awg0.conf
sudo systemctl start wg-quick-awg0
```

Finally confirm torrent traffic uses the VPN with a torrent IP test and that NAS
publishes no guest SSH or torrent ports. Evaluation and parser tests do not
substitute for these runtime checks.
