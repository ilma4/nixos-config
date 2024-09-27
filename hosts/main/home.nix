{ config, pkgs, ... }:

{
  imports = [
    ./../../common/home/base.nix
    ./../../common/home/personal.nix
     #<nixvim>.homeManagerModules.nixvim
  ];
  # Home Manager needs a bit of information about you and the paths it should
  # manage.
  home.username = "ilma4";
  home.homeDirectory = "/home/ilma4";

  nixpkgs.config.allowUnfree = true;

  # This value determines the Home Manager release that your configuration is
  # compatible with. This helps avoid breakage when a new Home Manager release
  # introduces backwards incompatible changes.
  #
  # You should not change this value, even if you update Home Manager. If you do
  # want to update the value, then make sure to first check the Home Manager
  # release notes.
  home.stateVersion = "24.05" ; # Please read the comment before changing.
}
