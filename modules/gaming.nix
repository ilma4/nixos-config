{
  config,
  lib,
  pkgs,
  ...
}: {
  programs.steam.enable = true;
  programs.gamescope = {
    enable = true;
    capSysNice = true;
  };

  programs.gamemode = {
    enable = true;
    enableRenice = true;
  };
}
