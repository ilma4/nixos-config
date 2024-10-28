{
  config,
  pkgs,
  ...
}: {
  imports = [
    # ./jetbrains.nix # FIXME: on 2024-10-05, usage of this idea, caused gpu crashes on wayland
  ];

  programs.firefox.enable = true;
  programs.thunderbird = {
    enable = true;
    profiles = {};
  };

  programs.chromium.enable = true;
  programs.obs-studio.enable = true;
  programs.vscode = {
    enable = true;
    #enableUpdateCheck = false;
  };

  programs.mpv.enable = true;

  xsession.enable = true;

  home.packages = with pkgs; [
    brave
    google-chrome
    vivaldi
    calibre
    slack
    telegram-desktop
    krita
    qbittorrent
    libsForQt5.qt5ct
    kdePackages.qt6ct
    xorg.xprop
    obsidian
    discord
    evince
    shotwell
    gnome.seahorse
  ];
}
