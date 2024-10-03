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

  home.packages = with pkgs ; [
    xdg-desktop-portal-wlr
    xdg-desktop-portal-gtk
  ];


  xdg.portal.extraPortals = [ pkgs.darkman pkgs.xdg-desktop-portal-wlr pkgs.xdg-desktop-portal-gtk ];
  xdg.portal.enable = true;
  xdg.portal.config = {
    preferred = {
      "org.freedesktop.impl.portal.Settings" = [ "darkman" ];
    };
    common = {
      "org.freedesktop.impl.portal.Secret" = [
        "gnome-keyring"
      ];
    };
    sway.default = [ "wlr" "gtk" ];
  };
}
