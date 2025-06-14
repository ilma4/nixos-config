{
  config,
  lib,
  pkgs,
  pkgs-unstable,
  modules,
  dotfiles,
  ...
}: {
  imports = [
    "${modules}/base.nix"
    "${modules}/macos.nix"
    "${modules}/personal.nix"
    "${modules}/dev.nix"
    "${modules}/graphics.nix"
    "${modules}/zed.nix"
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

    services.syncthing = {
      enable = true;
    };
    services.ollama = {
      enable = true;
      package = pkgs-unstable.ollama;
    };

    home.packages = with pkgs;
      [
        # clang
        # lldb
        colima # vm to run docker
        docker # docker cli

        texlab

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

        (pkgs.writeShellScriptBin "generate-random-password" "openssl rand 64 | sha512")
      ]
      ++ (with pkgs-unstable; [
        ollama
        llama-cpp
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

      ".config/aerospace/aerospace.toml".source = "${dotfiles}/aerospace.toml";
      ".config/resticprofile/profiles.toml".source = "${dotfiles}/resticprofile.toml";
    };
  };
}
