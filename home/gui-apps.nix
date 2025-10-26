{pkgs, ...}: {
  imports = [
    # ./jetbrains.nix # FIXME: on 2024-10-05, usage of this idea, caused gpu crashes on wayland
  ];

  programs.thunderbird.profiles = {};

  xsession.enable = true;

  home.packages = with pkgs; [
    libsForQt5.qt5ct
    kdePackages.qt6ct
    xorg.xprop
    evince
    shotwell
    seahorse
  ];
}
