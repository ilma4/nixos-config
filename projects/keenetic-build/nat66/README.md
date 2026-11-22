# NAT66 hooks

The hooks apply IPv6 MASQUERADE for a configured LAN prefix and uplink, and allow the corresponding forwarding in NDM’s forwarding chain. Keenetic must already advertise the selected ULA prefix to LAN clients and have a working IPv6 uplink. Set the actual Linux bridge and uplink device names in a local copy of `nat66.conf.example`.

On the router with OPKG storage initialized, these are the file locations:

| Source | Router path |
| --- | --- |
| Local NAT66 settings | `/opt/etc/nat66.conf` |
| `nat66.sh` | `/opt/etc/nat66.sh` |
| `initrc` | `/opt/etc/initrc` |
| `010-nat66.sh` | `/opt/etc/ndm/netfilter.d/010-nat66.sh` |
| `sh-wrapper` | `/opt/bin/sh` |

The `initrc` applies both rules when OPKG storage mounts. The netfilter hook reapplies rules after a native IPv6 table rebuild. The shell wrapper invokes BusyBox by its `ash` name. If the router has an existing OPKG startup script, integrate the NAT66 call into it so existing hooks still run.
