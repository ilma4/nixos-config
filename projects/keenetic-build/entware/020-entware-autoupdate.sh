#!/bin/sh
[ "$schedule" = EntwareUpdate ] && [ "$1" = start ] || exit 0
/opt/bin/sh /opt/etc/entware-autoupdate.sh </dev/null >/dev/null 2>&1 &
