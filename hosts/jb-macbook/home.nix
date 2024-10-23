args@{ config, lib, pkgs, modules, inputs, dotfiles, ... }:

{
  # Home Manager needs a bit of information about you and the
  # paths it should manage.
  home.username = "ilma4";
  home.homeDirectory = "/Users/ilma4";

  imports = [
    inputs.nixvim.homeManagerModules.nixvim
    "${modules}/base.nix"
  ];

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
    # calibre
    # anki
  ];


  home.file = {
    "itermNewWindow.scpt".text = ''
tell application "iTerm2" 
  create window with default profile 
end tell
'';
  };

  #home.file.".config/rclone/rclone.conf".source = config.lib.file.mkOutOfStoreSymlink "${dotfiles}/rclone.conf";
  
  # works but ugly
  #home.file.".config/rclone/rclone.conf".source = config.lib.file.mkOutOfStoreSymlink "/Users/ilma4/.config/nixos-config/dotfiles/rclone.conf";

  home.file.".config/rclone/rclone.conf".source = args.outOfStoreSymlink config  "rclone.conf";

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
}
