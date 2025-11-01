{
  config,
  lib,
  pkgs,
  pkgs-unstable,
  inputs,
  ...
}: {
  imports = let
    home = x: "${lib.flake-location}/home/${x}.nix";
  in [
    (home "base")
    (home "personal")
    (home "dev")
    (home "fonts")
    (home "zed")
    (home "raycast")
    "${lib.flake-location}/modules/work.nix"

    "${lib.flake-location}/modules/sops.nix"
    inputs.sops-nix.homeManagerModules.sops
  ];

  options = {
  };

  config = {
    home.username = "ilma4";
    i4.personal.enable = true;
    i4.fonts.enable = true;
    i4.zed.enable = true;
    i4.work.enable = true;
    i4.dev.enable = true;
    i4.raycast = {
      enable = true;
      scriptsPath = "Scripts";
    };

    rebuild-script = "sudo darwin-rebuild switch --flake ${config.home.homeDirectory}/.config/nixos-config#quicksilver";
    flake-source = "${config.home.homeDirectory}/.config/nixos-config";

    # sops-nix configuration
    sops = {
      secrets."wg.conf" = {
        sopsFile = "${lib.flake-location}/secrets/ru-torrent-nixos-vm-wg.conf";
        format = "binary";
      };
    };

    services.syncthing = {
      enable = true;
    };

    home.packages = with pkgs; [
      # clang
      # lldb

      ghc
      stack
      haskell-language-server

      texlab
      sops # for managing secrets
      age # for age key management
      meslo-lgs-nf # Meslo Nerd Font patched for Powerlevel10k

      /*
      (pkgs.writeShellScriptBin "system-upgrade" ''
        nix flake update --flake ${config.flake-location}
        nix-rebuild
        /opt/homebrew/bin/brew update -f
        /opt/homebrew/bin/brew upgrade --greedy
      '')
      */

      # FIXME: Remove this hack when issue is fixed: https://github.com/NixOS/nixpkgs/issues/339576
      (let
        bw =
          if pkgs.stdenv.isDarwin
          then "/opt/homebrew/bin/bw"
          else "${pkgs.bitwarden-cli}/bin/bw";
      in (pkgs.writeShellScriptBin "i4-generate-password" " ${bw} generate -u -l -s -n --length 30 --ambiguous"))

      (
        let
          CONFIG_LOCATION = "${config.home.homeDirectory}/.local/share/qbittorrent-container";
        in (pkgs.writeShellScriptBin "i4-qbittorrent-start" ''
          set -euo pipefail
          export PATH="${pkgs.podman-compose}/bin:${pkgs.podman}/bin:$PATH"

          mkdir -p "${CONFIG_LOCATION}"
          cp -f "${config.sops.secrets."wg.conf".path}" "${CONFIG_LOCATION}/wg.conf"
          export WG_CONFIG="${CONFIG_LOCATION}/wg.conf"

          ${pkgs.podman}/bin/podman compose -f "${lib.flake-location}/docker-compose/qbittorrent-compose.yaml" up --force-recreate --remove-orphans --detach --pull
        '')
      )
    ];

    # programs.zsh.profileExtra = "export JAVA_HOME=$(/usr/libexec/java_home)";

    programs.pandoc.enable = true;
    programs.texlive = {
      enable = true;
      extraPackages = tpkgs: {inherit (tpkgs) scheme-full;};
    };

    programs.ssh.matchBlocks = {
      "hetzer-storage" = {
        host = "u478838.your-storagebox.de";
        identityFile = "~/.ssh/jb-mac-to-hetzer-storage";
        user = "u478838";
      };
    };

    # home.sessionPath = ["/opt/homebrew/bin"]; # do not use, places before nix
    home.sessionVariables = {
      PATH = "$PATH:/opt/homebrew/bin";
      JAVA_HOME = "/Users/ilma4/Library/Java/JavaVirtualMachines/corretto-21.0.6/Contents/Home";
    };
    # programs.mpv.enable = true; # fixed in 24.11

    # RW symlinks, so apps can edits their configs
    home.file = let
      symlink = x: config.lib.file.mkOutOfStoreSymlink "${config.home.homeDirectory}/.config/nixos-config/dotfiles/${x}";
    in {
      # TODO: move those options to some common module
      ".config/rclone".source = symlink "rclone";
      ".config/karabiner".source = symlink "karabiner";
      ".config/zed".source = symlink "zed";
      ".gemini/settings.json".source = symlink "gemini_cli_settings.json";

      ".config/aerospace/aerospace.toml".source = "${lib.flake-location}/dotfiles/aerospace.toml";
      ".config/resticprofile/profiles.toml".source = "${lib.flake-location}/dotfiles/resticprofile.toml";
    };
  };
}
