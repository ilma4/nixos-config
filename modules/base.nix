{
  lib,
  pkgs,
  config,
  inputs,
  ...
}: let
  inherit (pkgs) stdenv;
in {
  options = {
  };
  imports = [
    inputs.home-manager.nixosModules.home-manager
    inputs.sops-nix.nixosModules.sops
  ];

  config = {
    hardware.enableAllFirmware = true;

    home-manager.useGlobalPkgs = true;
    home-manager.extraSpecialArgs = {
      inherit inputs;
      dotfiles = inputs.dotfiles;
      pkgs-unstable = inputs.pkgs-unstable;
      modules = inputs.home-manager-modules;
    };
  };
}
