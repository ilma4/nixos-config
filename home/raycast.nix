{
  config,
  lib,
  pkgs,
  ...
}:
with lib; let
  cfg = config.i4.raycast;

  # AppleScript files
  scriptFiles = {
    # "firefox.applescript" = ./raycast-scripts/firefox.applescript;
    "nas-mount-toggle.applescript" = ./raycast-scripts/nas-mount-toggle.applescript;
    "nix-rebuild.applescript" = ./raycast-scripts/nix-rebuild.applescript;
    "vivaldi.applescript" = ./raycast-scripts/vivaldi.applescript;
    "chrome.applescript" = ./raycast-scripts/chrome.applescript;
    "wh-1000xm5-connect.applescript" = ./raycast-scripts/wh-1000xm5-connect.applescript;
    "external-mic.applescript" = ./raycast-scripts/external-mic.applescript;
    "builtin-mic.applescript" = ./raycast-scripts/builtin-mic.applescript;
    "kill-eqmac.applescript" = ./raycast-scripts/kill-eqmac.applescript;

    "monitor-displayport.applescript" = pkgs.writeText "monitor-displayport.applescript" ''
      #!/usr/bin/osascript

      # Required parameters:
      # @raycast.schemaVersion 1
      # @raycast.title Monitor to DisplayPort
      # @raycast.mode silent
      # @raycast.packageName Monitors

      do shell script "${pkgs.monitor-input}/bin/monitor-input U2725QE=DP1"
    '';

    "monitor-hdmi.applescript" = pkgs.writeText "monitor-hdmi.applescript" ''
      #!/usr/bin/osascript

      # Required parameters:
      # @raycast.schemaVersion 1
      # @raycast.title Monitor to HDMI
      # @raycast.mode silent
      # @raycast.packageName Monitors

      do shell script "${pkgs.monitor-input}/bin/monitor-input U2725QE=HDMI1"
    '';

    "paste-from-markdown.sh" = pkgs.writeText "paste-from-markdown.sh" ''
      #!/bin/bash

      # Required parameters:
      # @raycast.schemaVersion 1
      # @raycast.title Paste from Markdown
      # @raycast.mode silent

      # Optional parameters:
      # @raycast.icon 📋
      # @raycast.packageName Clipboard
      # @raycast.description Convert Markdown in the clipboard to rich text and paste it into the frontmost app (e.g. Slack)

      # Takes the Markdown currently on the clipboard, renders it to HTML (GitHub
      # Flavored Markdown via md4c's md2html), puts both the rich-text (HTML) and a
      # plain-text fallback onto the macOS pasteboard, then pastes into the
      # frontmost app. Both flavors are hex-encoded before being embedded in the
      # AppleScript literal so arbitrary multi-line / quoted / Unicode content
      # survives intact. Technique:
      # https://joshuatz.com/posts/2023/writing-slack-messages-with-markdown/
      set -euo pipefail

      md="$(/usr/bin/pbpaste)"
      if [ -z "$md" ]; then
        echo "Clipboard is empty or holds no text"
        exit 1
      fi

      html="$(printf '%s' "$md" | ${pkgs.md4c}/bin/md2html --github)"

      html_hex="$(printf '%s' "$html" | /usr/bin/hexdump -ve '1/1 "%.2x"')"
      md_hex="$(printf '%s' "$md" | /usr/bin/hexdump -ve '1/1 "%.2x"')"

      /usr/bin/osascript -e "set the clipboard to {«class HTML»:«data HTML''${html_hex}», «class utf8»:«data utf8''${md_hex}»}"

      # Best-effort paste into the frontmost app. Needs Accessibility permission
      # for Raycast; without it the rich text simply stays on the clipboard.
      /usr/bin/osascript \
        -e 'delay 0.1' \
        -e 'tell application "System Events" to keystroke "v" using {command down}' || true
    '';
  };
in {
  options = {
    i4.raycast = {
      enable = lib.mkEnableOption "Enable Raycast AppleScript commands";
      scriptsPath = mkOption {
        type = types.str;
        default = "Scripts";
        description = "Relative path from home directory where Raycast scripts will be installed";
      };
      scripts = mkOption {
        type = types.listOf (types.enum (builtins.attrNames scriptFiles));
        default = builtins.attrNames scriptFiles;
        description = "Raycast AppleScript command files to install";
      };
    };
  };

  config = mkIf cfg.enable {
    # Install AppleScript files to ~/Scripts directory using home.file
    home.file =
      mapAttrs' (name: scriptPath: {
        name = "${cfg.scriptsPath}/${name}";
        value = {
          source = scriptPath;
          executable = true;
        };
      })
      (filterAttrs (name: _: elem name cfg.scripts) scriptFiles);
  };
}
