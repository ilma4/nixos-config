# Home Assistant through Pi and SSH

`ha-pi` runs the normal local Pi with an additional Home Assistant MCP server.
It preserves the current directory, Pi settings, credentials, and arguments.
The command is included whenever `i4.pi.enable` is enabled.

On `nas.local`, open Home Assistant's **Settings → Devices & Services → HA-MCP
Custom Component → HA-MCP Server → Configure** and set:

- **Network access:** `127.0.0.1`
- **Server port:** `9584`
- **Custom direct-access path:** `/mcp`
- **Remote access via webhook:** off

Save to reload the integration. `/mcp` is a public, fixed path; restricting the
listener to loopback and disabling the webhook makes access depend on SSH to
the NAS. Processes running on the NAS can also access it. No MCP secret or Home
Assistant token is stored on client devices.

Run `ha-pi`, or pass normal Pi arguments, for example `ha-pi --continue`.
Use `/mcp` inside Pi to inspect the connection. Pi's `mcp list` CLI does not load
extensions, so it does not list the server registered by this wrapper.
The status line shows `HA: connected` once Pi has registered the HA tools. The
first prompt waits up to ten seconds for them; `ha_get_overview` is directly
available and the remaining tools are discoverable through codemode. If SSH to
both NAS names fails, Pi starts with a warning and without HA-MCP. If SSH succeeds
but MCP tools do not load, Pi also starts with a warning; inspect `/mcp` for the
connection error.

The tunnel and MCP registration belong to the running `ha-pi` process. To resume
a Home Assistant conversation with access to its tools, use `ha-pi --continue`
or `ha-pi --resume`; resuming with plain `pi` does not open a tunnel.

Each invocation starts a separate SSH master forwarding local
`127.0.0.1:<random-free-port>` to NAS `127.0.0.1:9584`. It tries `nas.local`
first and falls back to `nas` if the SSH tunnel cannot be opened. A session-only
Pi extension registers `http://127.0.0.1:<random-free-port>/mcp`.
When Pi exits, the wrapper closes its SSH master,
removes its temporary control socket, and returns Pi's exit status.

Concurrent sessions choose their own free ports automatically. If another process
claims a chosen port before SSH binds it, the wrapper retries with a new port.
Use `HA_PI_PORT=19585 ha-pi` to request a fixed port; if that port is occupied,
startup fails without starting Pi. Only the local loopback interface is used.
Other local processes can use the forwarded endpoint
while the tunnel is open. Force-killing the wrapper with SIGKILL cannot run its
cleanup trap.
