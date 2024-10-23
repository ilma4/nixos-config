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

    #programs.firefox = {
    #  enable = true;
    #  package = pkgs.firefox-bin;
    #};
    programs.git.enable = true;

    programs.vscode.enable = true;

    services.syncthing = {
      enable = true;
    };

    home.packages = with pkgs; [
      obsidian
      telegram-desktop
      slack
      iterm2

      # Broken. FIXME: enable when fixed
      # calibre
      # anki
    ];


    #home.file."itermNewWindow.scpt".text = ''
#tell application "iTerm2" 
#  create window with default profile 
#end tell
#  '';

    # RW symlinks, so apps can edits their configs
    home.file = let symlink = x: config.lib.file.mkOutOfStoreSymlink "${config.dotfiles}/${x}"; in {
      ".config/rclone/rclone.conf".source = symlink "rclone.conf";
      ".config/karabiner/karabiner.json".source = symlink "karabiner/karabiner.json";
      ".config/karabiner/assets".source = symlink "karabiner/assets";
    };

    # This value determines the Home Manager release that your
    # configuration is compatible with. This helps avoid breakage
    # when a new Home Manager release introduces backwards
    # incompatible changes.
    #
    # You can update Home Manager without changing this value. See
    # the Home Manager release notes for a list of state version
    # changes in each release.
    home.stateVersion = "24.05";

    # Let Home Manager install and manage itself.
    programs.home-manager.enable = true;
  };
}
