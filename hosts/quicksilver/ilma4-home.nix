{
  config,
  lib,
  pkgs,
  inputs,
  ...
}: let
  # Secretive SSH agent socket (replaces the Bitwarden agent)
  secretiveSocket = "${config.home.homeDirectory}/Library/Containers/com.maxgoedjen.Secretive.SecretAgent/Data/socket.ssh";
in {
  imports = [
    inputs.sops-nix-darwin.homeManagerModules.sops

    ./common-home.nix
    ../../modules/sops.nix
    ./splash.nix
  ];

  config = {
    home.username = "ilma4";
    i4.personal.enable = true;
    i4.sops.enable = true;
    i4.raycast = {
      enable = true;
      scriptsPath = "Scripts";
      scripts = lib.mkOptionDefault ["brave.applescript"];
    };

    rebuild-script = "sudo darwin-rebuild switch --flake ${config.home.homeDirectory}/.config/nixos-config#quicksilver";
    flake-source = "${config.home.homeDirectory}/.config/nixos-config";

    services.syncthing = {
      enable = true;
    };

    home.packages = with pkgs; [
      (pkgs.writeShellScriptBin "openclaw-ssh" (builtins.readFile ../../scripts/openclaw-ssh.sh))

      lima

      sops # for managing secrets
      age # for age key management

      blueutil # bluetooth CLI, used by the WH-1000XM5 Raycast script
      terminal-notifier # auto-dismissing notifications for the WH-1000XM5 Raycast script
      switchaudio-osx # SwitchAudioSource, used by the mic-switching Raycast scripts

      (let
        bw = "${pkgs.bitwarden-cli}/bin/bw";
      in
        pkgs.writeShellScriptBin "i4-generate-password" ''
          set -euo pipefail
          exec ${bw} generate -u -l -s -n --length 30 --ambiguous
        '')
    ];

    programs.ssh.settings = {
      "*" = {
        IdentityAgent = secretiveSocket;
      };
      "hetzer-storage" = {
        header = "Host u478838.your-storagebox.de";
        Port = 23;
        IdentityFile = "~/.ssh/jb-mac-to-hetzer-storage";
        User = "u478838";
      };
    };

    home.sessionVariables = {
      LIMA_HOME = "/Volumes/Extra/android-lima";
      SSH_AUTH_SOCK = secretiveSocket;
      # JAVA_HOME = "/Users/ilma4/Library/Java/JavaVirtualMachines/corretto-21.0.6/Contents/Home";
    };

    # RW symlinks, so apps can edits their configs
    home.file = let
      symlink = x: config.lib.file.mkOutOfStoreSymlink "${config.home.homeDirectory}/.config/nixos-config/dotfiles/${x}";
    in {
      ".config/linearmouse/linearmouse.json".source = symlink "linearmouse/linearmouse.json";
      ".config/rclone".source = symlink "rclone";
      ".config/zed".source = symlink "zed";
    };
  };
}
