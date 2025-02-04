args @ {
  config,
  lib,
  pkgs,
  pkgs-unstable,
  modules,
  inputs,
  dotfiles,
  ...
}: {
  imports = [
    "${modules}/base.nix"
    "${modules}/macos.nix"
    "${modules}/personal.nix"
    "${modules}/dev.nix"
    "${modules}/graphics.nix"
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
    #home.homeDirectory = "/Users/ilma4";

    flake-location = "${config.home.homeDirectory}/.config/nixos-config";

    services.syncthing = {
      enable = true;
    };

    home.packages = with pkgs; [
      clang
      lldb
      colima
      docker
      
      (pkgs.writeShellScriptBin "system-upgrade" ''
        nix flake update --flake ${config.flake-location}
        nix-rebuild
        /opt/homebrew/bin/brew update -f
        /opt/homebrew/bin/brew upgrade --greedy
      '')

      (pkgs.writeShellScriptBin "generate-random-password" "openssl rand 64 | sha512")
    ] ++ (with pkgs-unstable ; [
      ollama
      llama-cpp
    ]);

    programs.zsh.profileExtra = "export JAVA_HOME=$(/usr/libexec/java_home)";

    programs.pandoc.enable = true;
    programs.texlive = {
      enable = true;
      extraPackages = (tpkgs: { inherit (tpkgs) scheme-full; });
    };

    # programs.mpv.enable = true; # fixed in 24.11

    # RW symlinks, so apps can edits their configs
    home.file = let
      symlink = x: config.lib.file.mkOutOfStoreSymlink "${config.dotfiles}/${x}";
    in {
      ".config/rclone".source = symlink "rclone";
      ".config/karabiner".source = symlink "karabiner";

      ".config/aerospace/aerospace.toml".source = "${dotfiles}/aerospace.toml";
    };
  };
}
