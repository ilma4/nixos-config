{
  config,
  lib,
  pkgs,
  constants,
  inputs,
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
      description = "Whether to add personal SSH public keys to the ilma4 user";
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
    ./deploy.nix
    ./backup/backup.nix
    ./swap.nix
    ./avahi.nix
    ./tpm2.nix
    ./console-disable-screen-timeout.nix
  ];

  config = {
    hardware.enableAllFirmware = mkDefault (!config.boot.isContainer);

    services.fwupd.enable = mkDefault (!config.boot.isContainer);

    time.timeZone = "Europe/Berlin";
    i18n.defaultLocale = "en_US.UTF-8";

    programs.neovim.enable = true;
    programs.nano.enable = true;
    programs.zsh.enable = true;

    services.dbus.implementation = "broker"; # better dbus, also required for home-assistant bluetooth integration

    services.fstrim.enable = mkDefault (!config.boot.isContainer); # Enable background periodic TRIM
    services.printing.enable = mkDefault (!config.boot.isContainer); # Enable CUPS to print documents.

    services.smartd = {
      enable = mkDefault (!config.boot.isContainer);
    };

    # TODO detect btrfs usage in `fileSystems` or in `services.btrfs.autoScrub.fileSystems` to enable automatically
    services.btrfs.autoScrub.interval = mkDefault "*-*-01 03:00:00"; # monthly at 03 am

    services.tailscale = {
      enable = mkDefault true;
      openFirewall = config.services.tailscale.enable;
      # Encrypt tailscaled's state file at rest, sealing the key to the TPM.
      # Only enable when a TPM 2.0 device is present, otherwise tailscaled fails to start.
      extraDaemonFlags = lib.optionals config.security.tpm2.enable ["--encrypt-state"];
    };

    services.openssh = {
      enable = mkDefault true;
      settings = {
        PasswordAuthentication = mkDefault false;

        # disable rsa algorithms
        HostKeyAlgorithms = "-rsa-sha2-512,-rsa-sha2-256";
        PubkeyAcceptedAlgorithms = "-rsa-sha2-512,-rsa-sha2-256,-ssh-rsa";
      };
      hostKeys = [
        # disable RSA key generation. It's less secure than old algorithms
        {
          type = "ed25519";
          path = "/etc/ssh/ssh_host_ed25519_key";
        }
      ];
    };

    environment.systemPackages = [
      (pkgs.writeShellScriptBin "i4-revision" ''
        set -euo pipefail
        echo '${config.system.configurationRevision}'
      '')
    ];
    system.configurationRevision = inputs.self.rev or inputs.self.dirtyRev or "null";

    security.rtkit.enable = mkDefault (!config.boot.isContainer); # realtime privileges

    users.users.ilma4 = lib.mkIf config.i4.user-ilma4.enable {
      isNormalUser = true;
      shell = pkgs.zsh;
      extraGroups = ["wheel"]; # Enable ‘sudo’ for the user.

      openssh.authorizedKeys.keys = lib.mkIf config.i4.my-ssh-key.enable constants.main-pub-keys;
    };
  };
}
