# HTTPS services through Tailscale

LAN and Tailscale clients use the same `https://<service>.ilma4.home.arpa` URLs
and the existing self-signed certificate. Each client must trust that certificate.
Pi-hole continues returning `192.168.1.33` for this domain.

## Configuration

The NAS advertises only `192.168.1.33/32` (HTTPS) and `192.168.1.200/32`
(Pi-hole). Tailscale subnet-route source NAT remains enabled.

Pi-hole retains its macvlan LAN interface and default gateway. A secondary bridge
(`10.78.0.0/30`, NAS `.1`, Pi-hole `.2`) allows the NAS to reach the container
without macvlan host isolation. The Pi-hole Compose service installs a host route
for `192.168.1.200/32` through `10.78.0.2` after startup and removes it on shutdown.

## Enable after deployment

1. Deploy the NAS configuration only when activation is requested.
2. The NAS routes `192.168.1.33/32` and `192.168.1.200/32` are already approved
   through [Terraform](../infra/tailscale/README.md).
3. Split DNS is enabled by default in Terraform: `192.168.1.200` is the nameserver
   restricted to `ilma4.home.arpa`, leaving global DNS unchanged.
4. Ensure the tailnet policy allows the intended clients TCP/UDP 53 to
   `192.168.1.200` and TCP 443 to `192.168.1.33` (TCP 80 is optional for redirects).
5. Enable Tailscale DNS on clients. Linux clients also need
   `sudo tailscale set --accept-routes=true`.

Route approval and access policy are separate requirements. Advertising only two
host routes does not itself restrict accessible ports on those addresses.

## Verify after deployment

- On the NAS, check `ip route get 192.168.1.200`: it must use `10.78.0.2`.
- Query `dig @192.168.1.200 dashboard.ilma4.home.arpa A`, then repeat with
  `+tcp`. Both must return `192.168.1.33`.
- From an outside network with Tailscale enabled, repeat both DNS queries and
  open `https://dashboard.ilma4.home.arpa` using the browser/OS resolver.
  On macOS use `dscacheutil -q host -a name dashboard.ilma4.home.arpa`;
  plain `dig` without an explicit server does not reliably test split DNS.
- Confirm the existing certificate is presented and trusted, and other services
  work using their existing URLs.
- Restart `pihole.service` and repeat the route and DNS checks.
- On the home LAN with Tailscale disabled, verify DNS and HTTPS still work.

Reference: https://tailscale.com/docs/features/subnet-routers
