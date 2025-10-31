{
  config,
  lib,
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
      scriptFiles;
  };
}
