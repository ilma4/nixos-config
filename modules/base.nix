args @ {
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

    time.timeZone = "Europe/Berlin";
    i18n.defaultLocale = "en_US.UTF-8";

    /*
    nixpkgs.config = {
      allowUnfree = true;
    };
    */

    # inputs.nixpkgs-unstable.config = config.nixpkgs.config;

    home-manager.useGlobalPkgs = true;
    home-manager.extraSpecialArgs = {
      inherit inputs;
      dotfiles = args.dotfiles;
      pkgs-unstable = args.pkgs-unstable;
      modules = args.home-manager-modules;
    };
  };
}
