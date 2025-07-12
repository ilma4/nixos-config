{
  config,
  lib,
  pkgs,
  ...
}:
with lib; let
  cfg = config.services.raycast;

  # AppleScript files
  scriptFiles = {
    "display-enable-scaling.applescript" = ./raycast-scripts/display-enable-scaling.applescript;
    "display-disable-scaling.applescript" = ./raycast-scripts/display-disable-scaling.applescript;
    "firefox.applescript" = ./raycast-scripts/firefox.applescript;
    "nas-mount-toggle.applescript" = ./raycast-scripts/nas-mount-toggle.applescript;
  };

  # Create derivation for raycast scripts
  raycastScripts = pkgs.runCommand "raycast-scripts" {} ''
    mkdir -p $out/bin
    ${concatStringsSep "\n" (mapAttrsToList (name: scriptPath: ''
        cp ${scriptPath} $out/bin/${name}
        chmod +x $out/bin/${name}
      '')
      scriptFiles)}
  '';
in {
  options = {
    services.raycast = {
      enable = mkEnableOption "Raycast script commands";

      scriptsPath = mkOption {
        type = types.str;
        default = "~/Scripts";
        description = "Path where Raycast scripts will be installed";
      };
    };
  };

  config = mkIf cfg.enable {
    # Install scripts to the system
    environment.systemPackages = [raycastScripts];

    # Create activation script to copy scripts to Raycast directory
    system.activationScripts.raycast-scripts = {
      text = ''
        echo "Setting up Raycast scripts..."

        # Create the scripts directory if it doesn't exist
        sudo -u ilma4 mkdir -p /Users/ilma4/scripts

        # Copy scripts from the nix store to the scripts directory
        ${concatStringsSep "\n" (mapAttrsToList (name: scriptPath: ''
            sudo -u ilma4 cp ${raycastScripts}/bin/${name} /Users/ilma4/scripts/${name}
            sudo -u ilma4 chmod +x /Users/ilma4/scripts/${name}
          '')
          scriptFiles)}

        echo "Raycast scripts installed successfully!"
      '';
    };
  };
}
