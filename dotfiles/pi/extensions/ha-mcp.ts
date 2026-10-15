import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";

// Loaded explicitly by ha-pi; ordinary Pi sessions don't connect to HA.
export default function (pi: ExtensionAPI) {
  const url = process.env.HA_PI_MCP_URL;
  if (!url) throw new Error("Run this extension through ha-pi to open the SSH tunnel.");

  pi.registerMcpServer("ha", {
    url,
    description: "Manage Home Assistant on nas.local through SSH.",
  });
}
