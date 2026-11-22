#!/bin/sh
# OpenSSH uses its own Entware runtime and account files.
PATH=/bin:/sbin:/usr/bin:/usr/sbin
export PATH
base=/opt/ssh-admin
daemon=$base/openssh/sshd
pidfile=/tmp/run/keenetic-ssh-admin/sshd.pid

running() {
    [ -r "$pidfile" ] || return 1
    read -r pid < "$pidfile" || return 1
    case "$pid" in ''|*[!0-9]*) return 1 ;; esac
    [ "/proc/$pid/exe" -ef "$daemon" ]
}

case "${1:-start}" in
    start)
        running && exit 0
        mkdir -p -m 700 /tmp/run/keenetic-ssh-admin
        export LD_LIBRARY_PATH="$base/openssh/lib"
        unset LD_PRELOAD
        "$daemon" -t -f "$base/sshd_config" &&
            "$daemon" -f "$base/sshd_config" -E /tmp/run/keenetic-ssh-admin/sshd.log
        ;;
    stop)
        if running; then kill "$pid"; fi
        ;;
    *) exit 2 ;;
esac
