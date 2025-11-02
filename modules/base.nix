{
  lib,
  inputs,
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
    inputs.hoopsnake.nixosModules.default # ssh via tailscale in initrd

    ./home-manager.nix
    ./nix-settings.nix
  ];

  config = {
    hardware.enableAllFirmware = true;

    time.timeZone = "Europe/Berlin";
    i18n.defaultLocale = "en_US.UTF-8";

    programs.neovim.enable = true;
    programs.nano.enable = true;
  };
}
