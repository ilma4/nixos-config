{ config, lib, pkgs, ... }:

{
  home.packages = with pkgs; [
    gnome.gnome-session
    gnome.eog # image viewer
    gnome.gvfs
    gnome-usage
    gnome-menus
    gnome.zenity
    gnome.nautilus
    terminator
    ptyxis
  ];
}
