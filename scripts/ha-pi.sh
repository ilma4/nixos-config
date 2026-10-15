#!/usr/bin/env bash
set -euo pipefail

# Each invocation owns its SSH master, even when the user's SSH config enables
# connection sharing. Closing this master never closes another SSH session.
tunnel_dir=$(mktemp -d "${TMPDIR:-/tmp}/ha-pi.XXXXXXXX")
tunnel_host=nas.local
cleanup() {
  local status=$?
  trap - EXIT
  @ssh@ -S "$tunnel_dir/control" -O exit "$tunnel_host" >/dev/null 2>&1 || true
  rm -rf "$tunnel_dir"
  exit "$status"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
trap 'exit 129' HUP

open_tunnel() {
  local attempt status
  for attempt in {1..5}; do
    port=${HA_PI_PORT:-$(@node@ -e '
      const server = require("node:net").createServer();
      server.listen(0, "127.0.0.1", () => {
        console.log(server.address().port);
        server.close();
      });
    ')}
    if @ssh@ -fNT -M -S "$tunnel_dir/control" \
      -o ControlPersist=no -o ExitOnForwardFailure=yes \
      -o ConnectTimeout=10 -o ServerAliveInterval=15 -o ServerAliveCountMax=3 \
      -L "127.0.0.1:$port:127.0.0.1:9584" "$tunnel_host" \
      2>"$tunnel_dir/ssh-error"; then
      cat "$tunnel_dir/ssh-error" >&2
      return 0
    else
      status=$?
      cat "$tunnel_dir/ssh-error" >&2
      # Another process can claim the port between discovery and SSH binding.
      # Retry that race, but preserve errors for an explicitly requested port.
      if [[ -n ${HA_PI_PORT:-} || $(<"$tunnel_dir/ssh-error") != *"Address already in use"* ]]; then
        return "$status"
      fi
    fi
  done
  return "$status"
}
if ! open_tunnel; then
  printf 'Could not open SSH tunnel to nas.local; trying nas.\n' >&2
  tunnel_host=nas
  open_tunnel
fi

export HA_PI_MCP_URL="http://127.0.0.1:$port/mcp"
pi --extension @extension@ "$@"
