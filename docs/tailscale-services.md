# HTTPS services through Tailscale

LAN and Tailscale clients use the same `https://<service>.ilma4.home.arpa` URLs
and the existing self-signed certificate. Each client must trust that certificate.
Pi-hole continues returning `192.168.1.33` for this domain.

## Configuration

The NAS advertises `192.168.0.0/23`. This is less specific than the home LAN's
`192.168.1.0/24`, so macOS and Windows clients at home prefer their LAN connection even
with Tailscale enabled. Away from home, Tailscale provides the fallback route.
The tailnet policy permits only `192.168.1.33` (NAS) and `192.168.1.200`
(Pi-hole) through this range; other destinations are denied. Direct connectivity
between Tailscale devices remains allowed over IPv4 and IPv6.
Tailscale subnet-route source NAT remains enabled.

Linux uses Tailscale policy routing, so prefix length alone does not establish
LAN priority there. Linux clients need a separate policy rule tied to their
connected LAN route if local bypass is required; this change targets macOS.

qBittorrent keeps its LAN-only authentication bypass: direct LAN requests skip
login, while requests arriving through Tailscale still require authentication.

Pi-hole retains its macvlan LAN interface and default gateway. A secondary bridge
(`10.78.0.0/30`, NAS `.1`, Pi-hole `.2`) allows the NAS to reach the container
without macvlan host isolation. The Pi-hole Compose service installs a host route
for `192.168.1.200/32` through `10.78.0.2` after startup and removes it on shutdown.

## Enable after deployment

1. Plan and apply the [Terraform changes](../infra/tailscale/README.md) when
   deployment is requested. This restricts subnet access and replaces the two
   old `/32` approvals with `192.168.0.0/23`. Remote access may be interrupted
   until the NAS advertises the new route; perform this migration from the LAN.
2. Deploy the NAS configuration to advertise the `/23`. Both old `/32` routes
   must be withdrawn; retaining them would still override the local `/24`.
3. Split DNS is enabled by default in Terraform: `192.168.1.200` is the nameserver
   restricted to `ilma4.home.arpa`, leaving global DNS unchanged.
4. Ensure the tailnet policy allows the intended clients TCP/UDP 53 to
   `192.168.1.200` and TCP 443 to `192.168.1.33` (TCP 80 is optional for redirects).
5. Enable Tailscale DNS on clients. Linux clients also need
   `sudo tailscale set --accept-routes=true`.

Route approval and access policy are separate requirements. The broader route
does not grant access to the whole subnet; the policy limits allowed destinations.

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
- On the home LAN with Tailscale enabled, run `route -n get 192.168.1.33` and
  `route -n get 192.168.1.200` on macOS: both must use the LAN interface rather
  than a `utun` interface.
- Request `https://qbittorrent.ilma4.home.arpa/api/v2/app/version` without
  cookies: expect HTTP 200 on the LAN and HTTP 403 through Tailscale remotely.
- From outside the LAN, verify other destinations in the `/23` remain blocked.
- With Tailscale disabled on the LAN, verify DNS and HTTPS still work.

Reference: https://tailscale.com/docs/features/subnet-routers

LAN route priority: https://tailscale.com/docs/reference/troubleshooting/network-configuration/lan-traffic-overlapping-subnets
