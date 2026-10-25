#!/usr/bin/env bash
set -euo pipefail

jump_host=nas
# Probe the SSH port without requesting an SSH-agent signature.
if /usr/bin/nc -4 -z -G 2 nas.local 22 >/dev/null 2>&1; then
    jump_host=nas.local
fi

exec /usr/bin/ssh -4 -o ConnectTimeout=10 -J "ilma4@${jump_host}" ilma4@10.77.0.2 "$@"
