{lib, ...}: {
  options = {
    isServer = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Is this machine a server. Configure podman for containers";
    };
  };

  imports = [
    ./home-manager.nix
    ./nix-settings.nix
  ];

  config = {
    hardware.enableAllFirmware = true;

    services.fwupd.enable = true;

    time.timeZone = "Europe/Berlin";
    i18n.defaultLocale = "en_US.UTF-8";

    programs.neovim.enable = true;
    programs.nano.enable = true;
  };
}
