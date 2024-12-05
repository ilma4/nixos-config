args @ {
  config,
  lib,
  pkgs,
  modules,
  inputs,
  dotfiles,
  ...
}: {
  imports = [
    "${modules}/base.nix"
  ];
  home.username = "nix-on-droid";
  home.homeDirectory = "/data/data/com.termux.nix/files/home";
  flake-location = "${config.home.homeDirectory}/.config/nixos-config";
  nixvim.enable = false;
}
