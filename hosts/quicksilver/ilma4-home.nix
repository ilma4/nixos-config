{
  config,
  lib,
  pkgs,
  pkgs-unstable,
  inputs,
  ...
}: {
  imports = [
    inputs.sops-nix-darwin.homeManagerModules.sops

    ./common-home.nix
    ../../modules/sops.nix
  ];

  config = {
    home.username = "ilma4";
    i4.personal.enable = true;
    i4.sops.enable = true;
    i4.raycast = {
      enable = true;
      scriptsPath = "Scripts";
    };

    rebuild-script = "sudo darwin-rebuild switch --flake ${config.home.homeDirectory}/.config/nixos-config#quicksilver";
    flake-source = "${config.home.homeDirectory}/.config/nixos-config";

    sops = {
      secrets."wg.conf" = {
        sopsFile = ../../secrets/ru-torrent-nixos-vm-wg.conf;
        format = "binary";
      };
    };

    services.syncthing = {
      enable = true;
    };

    home.packages = with pkgs; [
      pkgs-unstable.llama-cpp

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

      (let
        runQbittorrent = pkgs.writeShellScript "run-qbittorrent" (builtins.readFile ./../../scripts/run-qbittorrent.sh);
      in
        pkgs.writeShellScriptBin "i4-qbittorrent-start" ''
          set -euo pipefail
          export WG_CONFIG=${lib.escapeShellArg config.sops.secrets."wg.conf".path}
          exec ${runQbittorrent}
        '')
    ];

    programs.ssh.settings = {
      "*" = {
        IdentityAgent = "/Users/ilma4/Library/Containers/com.bitwarden.desktop/Data/.bitwarden-ssh-agent.sock";
      };
      "hetzer-storage" = {
        header = "Host u478838.your-storagebox.de";
        Port = 23;
        IdentityFile = "~/.ssh/jb-mac-to-hetzer-storage";
        User = "u478838";
      };
    };

    home.sessionVariables = {
      SSH_AUTH_SOCK = "/Users/ilma4/Library/Containers/com.bitwarden.desktop/Data/.bitwarden-ssh-agent.sock";
      # JAVA_HOME = "/Users/ilma4/Library/Java/JavaVirtualMachines/corretto-21.0.6/Contents/Home";
    };

    # RW symlinks, so apps can edits their configs
    home.file = let
      symlink = x: config.lib.file.mkOutOfStoreSymlink "${config.home.homeDirectory}/.config/nixos-config/dotfiles/${x}";
    in {
      ".config/linearmouse/linearmouse.json".source = symlink "linearmouse/linearmouse.json";
      ".config/rclone".source = symlink "rclone";
      ".config/karabiner".source = symlink "karabiner";
      ".config/zed".source = symlink "zed";
      ".gemini/settings.json".source = symlink "gemini_cli_settings.json";
    };
  };
}
