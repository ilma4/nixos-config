{
  config,
  lib,
  ...
}:
with lib; let
  cfg = config.programs.raycast;

  # AppleScript files
  scriptFiles = {
    "firefox.applescript" = ./raycast-scripts/firefox.applescript;
    "nas-mount-toggle.applescript" = ./raycast-scripts/nas-mount-toggle.applescript;
  };
in {
  options = {
    programs.raycast = {
      enable = mkOption {
        type = types.bool;
        default = true;
        description = "Enable Raycast AppleScript commands";
      };

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
