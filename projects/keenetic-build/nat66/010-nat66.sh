#!/bin/sh
# NDM invokes this after rebuilding IPv6 tables.
[ "$type" = ip6tables ] || exit 0
case "$table" in
    nat|filter) /opt/bin/sh /opt/etc/nat66.sh "$table" ;;
esac
