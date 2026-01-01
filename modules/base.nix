{
  config,
  lib,
  pkgs,
  ...
}: {
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
    programs.zsh.enable = true;

    services.dbus.implementation = "broker"; # better dbus, also required for home-assistant bluetooth integration

    services.fstrim.enable = lib.mkDefault true; # Enable background periodic TRIM

    services.openssh = {
      enable = lib.mkDefault true;
      settings = {
        PasswordAuthentication = lib.mkDefault false;

        # disable rsa algorithms
        HostKeyAlgorithms = "-rsa-sha2-512,-rsa-sha2-256";
        PubkeyAcceptedAlgorithms = "-rsa-sha2-512,-rsa-sha2-256,-ssh-rsa";
      };
    };

    security.rtkit.enable = lib.mkDefault true; # realtime privileges

    users.users.ilma4 = lib.mkIf config.i4.user-ilma4.enable {
      isNormalUser = true;
      shell = pkgs.zsh;
      extraGroups = ["wheel"]; # Enable ‘sudo’ for the user.

      openssh.authorizedKeys.keys = lib.mkIf config.i4.my-ssh-key.enable [
        "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIFdYWQA91YiviGcsXEVUf4/dbAU2So1AAa1qU6ZFlx7A"
      ];
    };
  };
}
