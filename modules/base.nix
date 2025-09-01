args @ {
  lib,
  inputs,
  config,
  pkgs-unstable,
  ...
}: {
  options = {
    isServer = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Is this machine a server. Configure podman for containers";
    };
  };

  imports = [
    inputs.home-manager.nixosModules.home-manager
    inputs.sops-nix.nixosModules.sops # secrets
    inputs.hoopsnake.nixosModules.default # ssh via tailscale in initrd

    "${lib.flake-location}/modules/home-manager.nix"
    "${lib.flake-location}/modules/nix-settings.nix"
  ];

  config = {
    hardware.enableAllFirmware = true;

    time.timeZone = "Europe/Berlin";
    i18n.defaultLocale = "en_US.UTF-8";

    /*
    nixpkgs.config = {
      allowUnfree = true;
    };
    */

    # inputs.nixpkgs-unstable.config = config.nixpkgs.config;
  };
}
