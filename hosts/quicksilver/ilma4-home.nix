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
      colima # vm to run docker
      docker # docker cli
      podman # podman cli
      podman-compose

      ghc
      stack
      haskell-language-server

      texlab
      sops # for managing secrets
      age # for age key management

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

      (pkgs.writeShellScriptBin "i4-qbittorrent-start" ''
        /usr/bin/env colima start

        mkdir -p "${config.home.homeDirectory}/.local/share/qbittorrent-container"
        cp "${config.sops.secrets."wg.conf".path}" "${config.home.homeDirectory}/.local/share/qbittorrent-container/wg.conf"
        export WG_CONFIG="${config.home.homeDirectory}/.local/share/qbittorrent-container/wg.conf"

        ${pkgs.docker}/bin/docker compose -f "${flake-location}/docker-compose/qbittorrent-compose.yaml" up --detach --quiet-pull --pull always
      '')
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
      ".config/rclone".source = symlink "rclone";
      ".config/karabiner".source = symlink "karabiner";
      ".config/zed".source = symlink "zed";

      ".config/aerospace/aerospace.toml".source = "${flake-location}/dotfiles/aerospace.toml";
      ".config/resticprofile/profiles.toml".source = "${flake-location}/dotfiles/resticprofile.toml";
    };
  };
}
