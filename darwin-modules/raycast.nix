{
  config,
  lib,
  pkgs,
  ...
}:
with lib; let
  cfg = config.services.raycast;

  # AppleScript files content
  scriptFiles = {
    "display-enable-scaling.applescript" = ''
      #!/usr/bin/osascript

      # Required parameters:
      # @raycast.schemaVersion 1
      # @raycast.title Enable scaling
      # @raycast.mode compact

      # Optional parameters:
      # @raycast.icon F

      do shell script "/Users/ilma4/.nix-profile/bin/display-internal-set-defaults"
    '';

    "display-disable-scaling.applescript" = ''
      #!/usr/bin/osascript

      # Required parameters:
      # @raycast.schemaVersion 1
      # @raycast.title Disable scaling
      # @raycast.mode compact

      # Optional parameters:
      # @raycast.icon F

      do shell script "/Users/ilma4/.nix-profile/bin/display-internal-full-res"
    '';

    "firefox.applescript" = ''
      #!/usr/bin/osascript

      # Required parameters:
      # @raycast.schemaVersion 1
      # @raycast.title Firefox
      # @raycast.mode compact

      # Optional parameters:
      # @raycast.icon F


      tell application "System Events"
          if (name of processes) contains "Firefox" then
              do shell script "/opt/homebrew/bin/firefox"
          else
              do shell script "open -a Firefox"
          end if
      end tell
    '';

    "nas-mount-toggle.applescript" = ''
      #!/usr/bin/osascript

      # Required parameters:
      # @raycast.schemaVersion 1
      # @raycast.title NAS mount toggle
      # @raycast.mode compact

      # Optional parameters:
      # @raycast.icon F


      set mountPoint to "/Users/ilma4/NoBackup/ilma4-nas"

      try
      	do shell script "mount | grep " & quoted form of mountPoint
      	-- Mounted, so unmount
      	do shell script "umount " & quoted form of mountPoint
      on error
      	-- Not mounted, so mount
      	do shell script "/Users/ilma4/.nix-profile/bin/rclone mount --daemon ilma4-nas:/ " & quoted form of mountPoint
      end try
    '';
  };

  # Create derivation for raycast scripts
  raycastScripts = pkgs.runCommand "raycast-scripts" {} ''
    mkdir -p $out/bin
    ${concatStringsSep "\n" (mapAttrsToList (name: content: ''
        cat > $out/bin/${name} << 'EOF'
        ${content}
        EOF
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
        default = "~/.local/share/raycast/scripts";
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
        mkdir -p /Users/ilma4/.local/share/raycast/scripts

        # Copy scripts from the nix store to the raycast directory
        ${concatStringsSep "\n" (mapAttrsToList (name: content: ''
            cp ${raycastScripts}/bin/${name} /Users/ilma4/.local/share/raycast/scripts/${name}
            chmod +x /Users/ilma4/.local/share/raycast/scripts/${name}
          '')
          scriptFiles)}

        # Set proper ownership
        chown -R ilma4:staff /Users/ilma4/.local/share/raycast/scripts

        echo "Raycast scripts installed successfully!"
      '';
    };
  };
}
