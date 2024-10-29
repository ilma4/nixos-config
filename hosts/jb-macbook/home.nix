args @ {
  config,
  lib,
  pkgs,
  modules,
  inputs,
  dotfiles,
  ...
}: {
  imports = [
    "${modules}/base.nix"
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
    home.homeDirectory = "/Users/ilma4";

    services.syncthing = {
      enable = true;
    };

    home.packages = with pkgs; [
      vifm

      #docker # docker support on macos is complicated

      # FIXME: gui apps on macos are broken, enable when get fixed
      #obsidian
      #telegram-desktop
      #slack
      #iterm2

      # Broken. FIXME: enable when fixed
      # calibre
      # anki
    ];

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
