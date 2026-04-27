{
  config,
  pkgs,
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
      sops # for managing secrets
      age # for age key management

      (let
        bw = "${pkgs.bitwarden-cli}/bin/bw";
      in
        pkgs.writeShellScriptBin "i4-generate-password" ''
          set -euo pipefail
          exec ${bw} generate -u -l -s -n --length 30 --ambiguous
        '')

      (pkgs.writeShellScriptBin "i4-qbittorrent-start" (builtins.readFile ./../../scripts/run-qbittorrent.sh))
    ];

    programs.ssh.matchBlocks = {
      "*" = {
        identityAgent = "/Users/ilma4/Library/Containers/com.bitwarden.desktop/Data/.bitwarden-ssh-agent.sock";
      };
      "hetzer-storage" = {
        port = 23;
        host = "u478838.your-storagebox.de";
        identityFile = "~/.ssh/jb-mac-to-hetzer-storage";
        user = "u478838";
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

      ".config/resticprofile/profiles.toml".source = ../../dotfiles/resticprofile.toml;
    };
  };
}
