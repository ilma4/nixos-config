#!/bin/sh
# MASQUERADE follows the current uplink SLAAC address.
PATH=/usr/sbin:/usr/bin:/sbin:/bin
export PATH
IP6=/usr/sbin/ip6tables
config=/opt/etc/nat66.conf
if [ ! -r "$config" ]; then
    printf 'Missing NAT66 settings: %s\n' "$config" >&2
    exit 1
fi
. "$config"
: "${LAN_PREFIX:?Set LAN_PREFIX in nat66.conf}"
: "${LAN:?Set LAN in nat66.conf}"
: "${WAN:?Set WAN in nat66.conf}"
ensure_nat() {
    "$IP6" -w 5 -t nat -C POSTROUTING -s "$LAN_PREFIX" -o "$WAN" -j MASQUERADE 2>/dev/null ||
        "$IP6" -w 5 -t nat -A POSTROUTING -s "$LAN_PREFIX" -o "$WAN" -j MASQUERADE
}
ensure_filter() {
    # Keep NDM's established/invalid handling, ACLs and hotspot checks ahead of us.
    "$IP6" -w 5 -t filter -C _NDM_FORWARD -i "$LAN" -o "$WAN" -s "$LAN_PREFIX" -j ACCEPT 2>/dev/null ||
        "$IP6" -w 5 -t filter -A _NDM_FORWARD -i "$LAN" -o "$WAN" -s "$LAN_PREFIX" -j ACCEPT
}
case "${1:-all}" in
    nat) ensure_nat ;;
    filter) ensure_filter ;;
    all) ensure_nat && ensure_filter ;;
    *) exit 2 ;;
esac
