args@{ config, lib, pkgs, modules, inputs, dotfiles, ... }:

{
  imports = [
    "${modules}/base.nix"
    inputs.nixvim.homeManagerModules.nixvim
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
    # Home Manager needs a bit of information about you and the
    # paths it should manage.
    home.username = "ilma4";
    home.homeDirectory = "/Users/ilma4";

    # Broken. FIXME: enable when fixed
    #programs.firefox = {
    #  enable = true;
    #  package = pkgs.firefox-bin;
    #};

    # nix on macos have issues with gui apps
    #programs.vscode.enable = true;

    services.syncthing = {
      enable = true;
    };

    home.packages = with pkgs; [
      vifm

      #docker

      # gui apps on macos are broken, enable when get fixed
      #obsidian
      #telegram-desktop
      #slack
      #iterm2

      # Broken. FIXME: enable when fixed
      # calibre
      # anki
    ];


    # RW symlinks, so apps can edits their configs
    home.file = let symlink = x: config.lib.file.mkOutOfStoreSymlink "${config.dotfiles}/${x}"; in {
      ".config/rclone/rclone.conf".source = symlink "rclone.conf";
      ".config/karabiner/karabiner.json".source = symlink "karabiner/karabiner.json";
      ".config/karabiner/assets".source = symlink "karabiner/assets";

      ".config/aerospace/aerospace.toml".source = "${dotfiles}/aerospace.toml";
    };
  };
}
