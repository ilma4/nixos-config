{ config, pkgs, inputs, modules, dotfiles, ... }:

{
  imports = [
    inputs.nixvim.homeManagerModules.nixvim
    "${modules}/base.nix"
    "${modules}/personal.nix"
  ];

  # Home Manager needs a bit of information about you and the paths it should
  # manage.
  home.username = "ilma4";
  home.homeDirectory = "/home/ilma4";

  # This value determines the Home Manager release that your configuration is
  # compatible with. This helps avoid breakage when a new Home Manager release
  # introduces backwards incompatible changes.
  #
  # You should not change this value, even if you update Home Manager. If you do
  # want to update the value, then make sure to first check the Home Manager
  # release notes.
  home.stateVersion = "24.05" ; # Please read the comment before changing.

  # The home.packages option allows you to install Nix packages into your
  # environment.
  home.packages = [
    pkgs.gnomeExtensions.gsconnect
    pkgs.gnomeExtensions.dash-to-dock
    pkgs.gnomeExtensions.caffeine
  ];

  programs.gnome-shell.enable = true;

  dconf = {
    enable = true;
    settings."org/gnome/shell" = {
      disable-user-extensions = false;
      enabled-extensions = with pkgs.gnomeExtensions; [
        blur-my-shell.extensionUuid
        gsconnect.extensionUuid
        "dash-to-dock"
        "gsconnect"
      ];
    };
  };

  # Let Home Manager install and manage itself.
  programs.home-manager.enable = true;
}
