{
  config,
  lib,
  pkgs,
  inputs,
  constants,
  ...
}: let
  resticIlma4Repo = constants.nas.restic-ilma4.location;
  resticIlma4RepoArg = lib.escapeShellArg resticIlma4Repo;
  appendOnlyResticCommand = pkgs.writeShellScript "i4-quicksilver-restic-append-only" ''
    set -euo pipefail

    umask 007
    exec ${lib.getExe pkgs.rclone} serve restic --stdio --append-only ${resticIlma4RepoArg}
  '';
  configureHddStandbyTimeout = ''
    set -euo pipefail

    ${pkgs.hdparm}/sbin/hdparm -S 12 /dev/sdb
    ${pkgs.hdparm}/sbin/hdparm -S 12 /dev/sda
  '';
in {
  imports = let
    modules = ../../modules;
  in [
    inputs.home-manager.nixosModules.home-manager
    inputs.sops-nix.nixosModules.sops

    ./hardware-configuration.nix
    ./hdd.nix

    "${modules}/sops.nix"
    "${modules}/notifications.nix"
    "${modules}/docker-compose.nix"
    ./samba.nix

    ./hdd-idle-guard.nix
    ./hoopsnake.nix
    # ./agent-dev-box.nix # issues with nixpkgs not having overlays in container unlike on host

    "${modules}/server.nix"
    ./docker-services/qbittorrent.nix

    ./docker-services/home-assistant.nix
    ./mqtt.nix
    ./docker-services/pdf-tools.nix

    ./docker-services/actual-budget.nix
    ./docker-services/paperless.nix
    ./docker-services/immich/immich.nix

    ./docker-services/grafana.nix
    ./docker-services/node-exporter.nix

    ./docker-services/traefik.nix
    ./docker-services/error-page.nix

    ./docker-services/audiobookshelf.nix
    ./docker-services/mallard.nix
    ./incus-openclaw.nix

    # ./docker-services/rssalchemy.nix

    ./dashboard.nix
    "${./prometheus}/prometheus.nix"
    ./docker-services/pihole.nix
    # ./lidarr.nix
  ];

  i4.swap.zswapEnable = true;
  i4.swap.swapEnable = true;
  i4.avahi.enable = true;
  i4.sops.enable = true;
  i4.notifications.enable = true;
  i4.dockerComposeEnable = true;
  i4.initrd-ssh.enable = true;
  i4.deploy.enable = true;

  # Use the systemd-boot EFI boot loader.
  boot.loader = {
    efi = {
      canTouchEfiVariables = true;
      efiSysMountPoint = "/boot/efi";
    };
    grub = {
      enable = true;
      efiSupport = true;
      # efiInstallAsRemovable = true; # in case canTouchEfiVariables doesn't work for your system
      device = "nodev";
    };
  };

  hardware.bluetooth.enable = true; # enables support for Bluetooth
  hardware.bluetooth.powerOnBoot = true; # powers up the default Bluetooth controller on boot

  networking.hostName = "nas"; # Define your hostname.

  networking.nameservers = ["192.168.1.200" "1.1.1.1" "8.8.8.8"];

  users.users.ilma4.openssh.authorizedKeys.keys = [
    ''command="${appendOnlyResticCommand}",no-agent-forwarding,no-port-forwarding,no-X11-forwarding,no-pty,no-user-rc ${constants.quicksilver.backup-pub-key}''
  ];

  sops.secrets."restic/server" = {
    owner = "root";
    group = "root";
  };
  sops.secrets."restic_password/ilma4_legacy" = {
    owner = "root";
    group = "root";
  };

  i4.backup = {
    enable = true;
    metrics = {
      enable = true;
      pushgatewayBaseUrl = "http://127.0.0.1:9091";
    };
    paths = ["/srv"];
    backupHour = 4;
    backupMinute = 0;
    localRepo = {
      location = "/mnt/hdd/restic-server";
      passwordFile = "/run/secrets/restic/server";
    };
  };

  # suspend sata hdds after 1 minute of inactivity
  systemd.services.hdd-standby-timeout = {
    description = "Configure SATA HDD standby timeout";
    wantedBy = ["multi-user.target"];
    script = configureHddStandbyTimeout;
    serviceConfig.Type = "oneshot";
  };

  systemd.services.hdd-standby-timeout-resume = {
    description = "Configure SATA HDD standby timeout after resume";
    wantedBy = ["sleep.target"];
    before = ["sleep.target"];
    unitConfig.StopWhenUnneeded = true;
    script = ''
      set -euo pipefail
      :
    '';
    preStop = configureHddStandbyTimeout;
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
  };

  services.prometheus.node-exporter-docker.enable = true;
  services.printing.enable = false;

  # accept all incoming connections from tailscale
  networking.firewall.trustedInterfaces = ["tailscale0"];

  services.btrfs.autoScrub.enable = true;

  home-manager.users = {
    "ilma4" = import ./home.nix;
  };

  environment.pathsToLink = ["/share/zsh"];

  environment.systemPackages = with pkgs; [
    config.boot.kernelPackages.x86_energy_perf_policy
    hdparm
    smartmontools
    vim # Do not forget to add an editor to edit configuration.nix! The Nano editor is also installed by default.
  ];

  services.smartd.extraOptions = ["--interval=86400"]; # run checks every 24 hours # TODO reset to default when switch to SSD

  security.sudo.extraRules = [
    {
      users = [config.users.users.ilma4.name];
      commands = [
        {
          command = "ALL";
          options = ["NOPASSWD"];
        }
      ];
    }
  ];

  # programs.nix-ld.enable = true;

  # This option defines the first version of NixOS you have installed on this particular machine,
  # and is used to maintain compatibility with application data (e.g. databases) created on older NixOS versions.
  #
  # Most users should NEVER change this value after the initial install, for any reason,
  # even if you've upgraded your system to a new NixOS release.
  #
  # This value does NOT affect the Nixpkgs version your packages and OS are pulled from,
  # so changing it will NOT upgrade your system - see https://nixos.org/manual/nixos/stable/#sec-upgrading for how
  # to actually do that.
  #
  # This value being lower than the current NixOS release does NOT mean your system is
  # out of date, out of support, or vulnerable.
  #
  # Do NOT change this value unless you have manually inspected all the changes it would make to your configuration,
  # and migrated your data accordingly.
  #
  # For more information, see `man configuration.nix` or https://nixos.org/manual/nixos/stable/options#opt-system.stateVersion .
  system.stateVersion = "24.05"; # Did you read the comment?
}
