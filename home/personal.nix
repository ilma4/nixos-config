{ config, pkgs, ... }:

{
  home.packages = with pkgs; [
    screen
  ];
}
