i @ {
  lib,
  pkgs,
  config,
  inputs,
  ...
}: {
  options = {
  };
  imports = [
    inputs.home-manager.nixosModules.home-manager
    inputs.sops-nix.nixosModules.sops
    inputs.hoopsnake.nixosModules.default # ssh via tailscale in initrd
  ];

  config = {
    hardware.enableAllFirmware = true;

    home-manager.useGlobalPkgs = true;
    home-manager.extraSpecialArgs = {
      inherit inputs;
      dotfiles = i.dotfiles;
      pkgs-unstable = i.pkgs-unstable;
      modules = i.home-manager-modules;
    };
  };
}
