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
    flake-configuration = "DE-UNIT-1832"; # TODO: set better name and sync with flakes.nix

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

    home.packages = with pkgs;
      [
        # clang
        # lldb
        colima # vm to run docker
        docker # docker cli

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

        (pkgs.writeShellScriptBin "display-internal-set-defaults" ''
          displayplacer "id:37D8832A-2D66-02CA-B9F7-8F30A301B230 res:1512x982 hz:120 color_depth:8 enabled:true scaling:on origin:(0,0) degree:0"
        '')

        (pkgs.writeShellScriptBin "display-internal-full-res" ''
          displayplacer "id:37D8832A-2D66-02CA-B9F7-8F30A301B230 res:3024x1964 hz:120 color_depth:8 enabled:true scaling:off origin:(0,0) degree:0"
        '')

        # FIXME: Remove this hack when issue is fixed: https://github.com/NixOS/nixpkgs/issues/339576
        (let
          bw =
            if pkgs.stdenv.isDarwin
            then "/opt/homebrew/bin/bw"
            else "${pkgs.bitwarden-cli}/bin/bw";
        in (pkgs.writeShellScriptBin "i4-generate-password" " ${bw} generate -u -l -s -n --length 30 --ambiguous"))

        (pkgs.writeShellScriptBin "i4-qbittorrent-start" ''
          if ! colima status | grep -q "Running"; then
            echo "Starting colima..."
            colima start
          fi

          WG_CONFIG="${config.sops.secrets."wg.conf".path}"
          [ ! -f "$WG_CONFIG" ] && { echo "Error: WireGuard config not found"; exit 1; }

          # Parse WireGuard config
          export WIREGUARD_ADDRESSES=$(grep "^Address" "$WG_CONFIG" | cut -d'=' -f2 | xargs)
          export WIREGUARD_PRIVATE_KEY=$(grep "^PrivateKey" "$WG_CONFIG" | cut -d'=' -f2 | xargs)
          export WIREGUARD_PUBLIC_KEY=$(grep "^PublicKey" "$WG_CONFIG" | cut -d'=' -f2 | xargs)
          export WIREGUARD_PRESHARED_KEY=$(grep "^PresharedKey" "$WG_CONFIG" | cut -d'=' -f2 | xargs)
          ENDPOINT=$(grep "^Endpoint" "$WG_CONFIG" | cut -d'=' -f2 | xargs)
          export WIREGUARD_ENDPOINT_IP=$(echo "$ENDPOINT" | cut -d':' -f1)
          export WIREGUARD_ENDPOINT_PORT=$(echo "$ENDPOINT" | cut -d':' -f2)

          # Validate required fields
          [ -z "$WIREGUARD_ADDRESSES" ] && { echo "Error: Missing Address"; exit 1; }
          [ -z "$WIREGUARD_PRIVATE_KEY" ] && { echo "Error: Missing PrivateKey"; exit 1; }
          [ -z "$WIREGUARD_PUBLIC_KEY" ] && { echo "Error: Missing PublicKey"; exit 1; }
          [ -z "$WIREGUARD_ENDPOINT_IP" ] && { echo "Error: Missing Endpoint IP"; exit 1; }
          
          [ -z "$WIREGUARD_ENDPOINT_PORT" ] && { echo "Error: Missing Endpoint port"; exit 1; }

          env WIREGUARD_ENDPOINT_IP=$WIREGUARD_ENDPOINT_IP ${pkgs.docker}/bin/docker compose -f "${flake-location}/docker-compose/qbittorrent-compose.yaml" up -d
        '')
      ]
      ++ (with pkgs-unstable; [
        llama-cpp
        gemini-cli
      ]);

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
