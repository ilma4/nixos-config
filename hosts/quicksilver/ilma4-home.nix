{
  config,
  lib,
  pkgs,
  pkgs-unstable,
  flake-location,
  inputs,
  ...
}: {
  imports = let
    home = x: "${flake-location}/home/${x}.nix";
  in [
    (home "base")
    (home "macos")
    (home "personal")
    (home "dev")
    (home "graphics")
    (home "zed")
    (home "raycast")
    "${flake-location}/modules/sops.nix"
    inputs.sops-nix.homeManagerModules.sops
  ];

  options = {
    dotfiles = lib.mkOption {
      type = lib.types.str;
      apply = toString;
      default = "${config.home.homeDirectory}/.config/nixos-config/dotfiles";
      example = "${config.home.homeDirectory}/.config/nixos-config/dotfiles";
      description = "Location of the dotfiles working copy";
    };
  };

  config = {
    home.username = "ilma4";

    flake-location = "${config.home.homeDirectory}/.config/nixos-config";
    rebuild-script = "sudo darwin-rebuild switch --flake ${config.flake-location}#quicksilver";

    # sops-nix configuration
    sops = {
      secrets."wg.conf" = {
        sopsFile = "${flake-location}/secrets/ru-torrent-nixos-vm-wg.conf";
        format = "binary";
      };
    };

    services.syncthing = {
      enable = true;
    };

    programs.raycast = {
      enable = true;
      scriptsPath = "Scripts";
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

      (pkgs.writeShellScriptBin "system-upgrade" ''
        nix flake update --flake ${config.flake-location}
        nix-rebuild
        /opt/homebrew/bin/brew update -f
        /opt/homebrew/bin/brew upgrade --greedy
      '')

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

          ${pkgs.podman}/bin/podman compose -f "${flake-location}/docker-compose/qbittorrent-compose.yaml" up --force-recreate --remove-orphans --detach --pull
        '')
      )
    ];

    # programs.zsh.profileExtra = "export JAVA_HOME=$(/usr/libexec/java_home)";

    programs.pandoc.enable = true;
    programs.texlive = {
      enable = true;
      extraPackages = tpkgs: {inherit (tpkgs) scheme-full;};
    };

    # home.sessionPath = ["/opt/homebrew/bin"]; # do not use, places before nix
    home.sessionVariables = {
      PATH = "$PATH:/opt/homebrew/bin";
    };
    # programs.mpv.enable = true; # fixed in 24.11

    home.activation = {
      resticprofile-reschedule = let
        resticprofile = "${pkgs.resticprofile}/bin/resticprofile";
      in
        lib.hm.dag.entryAfter ["writeBoundary"] ''
          /usr/bin/sudo -u ilma4 ${resticprofile} unschedule --all
          /usr/bin/sudo -u ilma4 ${resticprofile} schedule --all
        '';
    };

    # RW symlinks, so apps can edits their configs
    home.file = let
      symlink = x: config.lib.file.mkOutOfStoreSymlink "${config.dotfiles}/${x}";
    in {
      # TODO: move those options to some common module
      ".config/rclone".source = symlink "rclone";
      ".config/karabiner".source = symlink "karabiner";
      ".config/zed".source = symlink "zed";
      ".gemini/settings.json".source = symlink "gemini_cli_settings.json";

      ".config/aerospace/aerospace.toml".source = "${flake-location}/dotfiles/aerospace.toml";
      ".config/resticprofile/profiles.toml".source = "${flake-location}/dotfiles/resticprofile.toml";
    };
  };
}
