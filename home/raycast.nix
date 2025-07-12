{
  config,
  lib,
  pkgs,
  ...
}:
with lib; let
  # AppleScript files
  scriptFiles = {
    "display-enable-scaling.applescript" = ./raycast-scripts/display-enable-scaling.applescript;
    "display-disable-scaling.applescript" = ./raycast-scripts/display-disable-scaling.applescript;
    "firefox.applescript" = ./raycast-scripts/firefox.applescript;
    "nas-mount-toggle.applescript" = ./raycast-scripts/nas-mount-toggle.applescript;
  };
in {
  config = {
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
