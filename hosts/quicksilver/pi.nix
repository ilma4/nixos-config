{
  lib,
  pkgs,
  ...
}: {
  # home.file.".pi/agent/models.json".source = ./pi/models.json;
  home.file.".pi/agent/extensions/notify-finish.ts".source = ./pi/extensions/notify-finish.ts;
  home.file.".pi/agent/extensions/ij-proxy-mcp-fix.ts".source = ./pi/extensions/ijproxy-mcp-agents-md-fix.ts;
}
