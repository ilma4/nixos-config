{ config, pkgs, ... }:

{
  imports = [
  ];

  programs.firefox.enable = true;
  programs.thunderbird = {
    enable = true;
    profiles = {};
  };
  programs.chromium.enable = true;
  programs.obs-studio.enable = true;
  programs.vscode.enable = true;
  programs.mpv.enable = true;

  xsession.enable = true;

  
  home.packages = with pkgs ; [
    brave
    google-chrome
    calibre
    slack
    telegram-desktop
    krita
    qbittorrent
    libsForQt5.qt5ct
    kdePackages.qt6ct
    xorg.xprop
    obsidian
    gamescope
    d-spy
  ];

}
