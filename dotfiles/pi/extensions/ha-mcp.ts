import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";

// Loaded explicitly by ha-pi; ordinary Pi sessions don't connect to HA.
export default function (pi: ExtensionAPI) {
  const url = process.env.HA_PI_MCP_URL;
  if (url) {
    pi.registerMcpServer("ha", {
      url,
      description: "Manage Home Assistant on the NAS through SSH.",
      // Pi waits for direct tools before the first prompt. Keep the rest of
      // the catalogue discoverable without declaring all 77 tools to the model.
      toolExposure: { ha_get_overview: "direct" },
    });
  }

  let timer: ReturnType<typeof setTimeout> | undefined;
  const stopChecking = () => {
    clearTimeout(timer);
    timer = undefined;
  };
  pi.on("session_shutdown", stopChecking);
  pi.on("session_start", (_event, ctx) => {
    stopChecking();
    if (!url) {
      ctx.ui.setStatus("ha-mcp", "HA: unavailable");
      ctx.ui.notify("SSH to nas.local and nas failed. Pi started without Home Assistant MCP.", "warning");
      return;
    }

    ctx.ui.setStatus("ha-mcp", "HA: connecting");
    const deadline = Date.now() + 10_000;
    const checkTools = () => {
      if (pi.getAllTools().some((tool) => tool.name === "mcp__ha__ha_get_overview")) {
        ctx.ui.setStatus("ha-mcp", "HA: connected");
      } else if (Date.now() < deadline) {
        timer = setTimeout(checkTools, 50);
      } else {
        ctx.ui.setStatus("ha-mcp", "HA: unavailable");
        ctx.ui.notify("Home Assistant MCP tools did not load. Use /mcp to inspect or reconnect ha.", "warning");
      }
    };
    // Return from session_start so Pi can apply MCP's background tool registrations.
    timer = setTimeout(checkTools, 0);
  });
}
