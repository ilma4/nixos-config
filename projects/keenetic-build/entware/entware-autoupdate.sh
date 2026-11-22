#!/bin/sh
PATH=/opt/bin:/opt/sbin:/usr/bin:/usr/sbin:/bin:/sbin
export PATH
unset LD_PRELOAD LD_LIBRARY_PATH

lock=/tmp/entware-autoupdate.lock
mkdir "$lock" 2>/dev/null || exit 0
trap 'rmdir "$lock"' EXIT
trap 'exit 1' INT TERM
trap '' HUP

exec >/tmp/entware-autoupdate.log 2>&1
date
if /opt/bin/opkg update && /opt/bin/opkg upgrade; then
    logger -t entware-autoupdate 'Package update completed'
else
    logger -t entware-autoupdate 'Package update failed. See /tmp/entware-autoupdate.log'
    exit 1
fi
