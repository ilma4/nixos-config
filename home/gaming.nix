{
  config,
  lib,
  pkgs,
  ...
}: {
  home.packages = with pkgs; [
    prismlauncher
    heroic
    wine
  ];

  programs.gamescope.enable = true;
  programs.gamemode = {
    enable = true;
    enableRenice = true;
  };

  programs.steam.enable = true;
}
