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

  services.playerctld.enable = true;

  services.easyeffects.enable = true;

  home.file = {
    ".config/easyeffects/irs/Sony MDR-7506 minimum phase 48000 Hz.irs".source = ../../dotfiles/easyeffects/${"Sony MDR-7506 minimum phase 48000 Hz.irs"} ;
    ".config/easyeffects/output/Sony MDR-7506 no bass boost.json".source = ../../dotfiles/easyeffects/${"Sony MDR-7506 no bass boost.json"};
  };

  
  services.ssh-agent.enable = true;
  programs.ssh = {
    enable = true;
    addKeysToAgent = "1h";
  };

  programs.gpg.enable = true;
  services.gpg-agent = {
    enable = true;
    pinentryPackage = pkgs.pinentry-curses;
  };

  xdg.enable = true;
  xdg.mime.enable = true; # .desktop entryes for apps
  xdg.portal.enable = true;
  xdg.portal.extraPortals = [ pkgs.xdg-desktop-portal-wlr ];
  xdg.portal.configPackages = [ pkgs.sway ];

  home.packages = with pkgs; [
    playerctl
  ];
}
