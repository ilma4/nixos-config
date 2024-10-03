{ config, pkgs, ... }:

{
  imports = [
    ./../../common/home/base.nix
    ./../../common/home/personal.nix
    ./home-gui.nix
  ];

  home.username = "ilma4";
  home.homeDirectory = "/home/ilma4";


  targets.genericLinux.enable = true;
  xdg.mime.enable = true;

  services.darkman.settings = {
    # Berlin 
    lat = 52.5;
    lng = 13.4;

    usegeoclue = true;
  };

  services.easyeffects.enable = true;

  services.darkman.darkModeScripts = {
    gtk-theme = ''
      ${pkgs.dconf}/bin/dconf write /org/gnome/desktop/interface/color-scheme "'prefer-dark'"
      ${pkgs.dconf}/bin/dconf write /org/gnome/desktop/interface/gtk-theme "'Yaru-dark'"
    '';
  };

  services.darkman.lightModeScripts = {
    gtk-theme = ''
      ${pkgs.dconf}/bin/dconf write /org/gnome/desktop/interface/color-scheme "'prefer-light'"
      ${pkgs.dconf}/bin/dconf write /org/gnome/desktop/interface/gtk-theme "'Yaru-light'"
    '';
  };

  #xdg.enable = true;
  #xdg.portal.enable = true;
  xdg.portal.extraPortals = [ pkgs.darkman pkgs.xdg-desktop-portal-wlr ];
  xdg.portal.config = {
    common = {
      "org.freedesktop.impl.portal.Settings" = [ "darkman" ];
      "org.freedesktop.portal.Settings" = [ "darkman" ];
    };
  };
}
