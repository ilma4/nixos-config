{
  config,
  lib,
  pkgs,
  constants,
  ...
}: let
  mkDefault = lib.mkDefault;
in {
  options = {
    isServer = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Is this machine a server. Configure podman for containers";
    };
    i4.user-ilma4.enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Whether to create the \"ilma4\" user";
    };
    i4.my-ssh-key.enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Whether to add main SSH public key to the ilma4 user";
    };
    i4.initrd-ssh.enable = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Enable SSH in initrd (includes initrd systemd + networking)";
    };
  };

  imports = [
    ./home-manager.nix
    ./nix-settings.nix
    ./initrd-ssh.nix
  ];

  config = {
    hardware.enableAllFirmware = true;

    services.fwupd.enable = true;

    time.timeZone = "Europe/Berlin";
    i18n.defaultLocale = "en_US.UTF-8";

    programs.neovim.enable = true;
    programs.nano.enable = true;
    programs.zsh.enable = true;

    services.dbus.implementation = "broker"; # better dbus, also required for home-assistant bluetooth integration

    services.fstrim.enable = mkDefault true; # Enable background periodic TRIM
    services.printing.enable = mkDefault true; # Enable CUPS to print documents.

    services.smartd = {
      enable = true;
    };

    # TODO detect btrfs usage in `fileSystems` or in `services.btrfs.autoScrub.fileSystems` to enable automatically
    services.btrfs.autoScrub.interval = mkDefault "*-*-01 03:00:00"; # monthly at 03 am

    services.tailscale = {
      enable = mkDefault true;
      openFirewall = config.services.tailscale.enable;
    };

    services.openssh = {
      enable = mkDefault true;
      settings = {
        PasswordAuthentication = mkDefault false;

        # disable rsa algorithms
        HostKeyAlgorithms = "-rsa-sha2-512,-rsa-sha2-256";
        PubkeyAcceptedAlgorithms = "-rsa-sha2-512,-rsa-sha2-256,-ssh-rsa";
      };
    };

    security.rtkit.enable = mkDefault true; # realtime privileges

    users.users.ilma4 = lib.mkIf config.i4.user-ilma4.enable {
      isNormalUser = true;
      shell = pkgs.zsh;
      extraGroups = ["wheel"]; # Enable ‘sudo’ for the user.

      openssh.authorizedKeys.keys = lib.mkIf config.i4.my-ssh-key.enable [
        constants.main-pub-key
      ];
    };
  };
}
