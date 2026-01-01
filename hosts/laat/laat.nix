args @ {
  config,
  pkgs,
  lib,
  myLib,
  inputs,
  ...
}: {
  imports = let
    modules = ../../modules;
  in [
    inputs.home-manager.nixosModules.home-manager
    inputs.sops-nix.nixosModules.sops

    ./hardware-configuration.nix
    ./hdd.nix

    "${modules}/avahi.nix"
    "${modules}/zram.nix"
    "${modules}/sops.nix"
    "${modules}/docker-compose.nix"
    ./samba.nix

    ./hdd-idle-guard.nix

    "${modules}/server.nix"
    ./docker-services/qbittorrent.nix

    ./docker-services/home-assistant.nix
    ./docker-services/pdf-tools.nix

    ./docker-services/actual-budget.nix
    ./docker-services/paperless.nix
    ./docker-services/immich/immich.nix

    ./docker-services/grafana.nix
    ./docker-services/node-exporter.nix

    ./docker-services/nginx-reverse-proxy.nix

    # ./docker-services/rssalchemy.nix

    "${modules}/backup.nix"

    # ./dashboard.nix
    "${./prometheus}/prometheus.nix"
    ./docker-services/pihole.nix
    # ./lidarr.nix
  ];

  i4.zram.enable = true;
  i4.avahi.enable = true;
  i4.sops.enable = true;
  i4.dockerComposeEnable = true;
  i4.backup.enable = true;

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

  networking.hostName = "laat"; # Define your hostname.

  boot.initrd.systemd.enable = true;
  boot.initrd.network.enable = true;

  boot.initrd.network.ssh = {
    enable = true;
    hostKeys = ["/etc/secrets/initrd/ssh_host_ed25519_key"];
    authorizedKeys = ["ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIM4gqAl3ZqveXhNkOrOb6tv9EBbSfV3RlvvP778PzAyN ilma4@DE-UNIT-1832"];
    # authorizedKeyFiles = [ config.sops.secrets.ssh-jb-mac-to-ilma4-pub.path ];
  };

  # console = {
  #   font = "Lat2-Terminus16";
  #   keyMap = "us";
  #   useXkbConfig = true; # use xkb.options in tty.
  # };

  sops.secrets."restic/server" = {
    owner = "root";
    group = "root";
  };
  environment.etc."resticprofile/profiles.toml".source = ../../dotfiles/resticprofile/laat.toml;

  # suspend sata hdds after 1 minute of inactivity
  powerManagement.powerUpCommands = ''
    ${pkgs.hdparm}/sbin/hdparm -S 12 /dev/sdb
    ${pkgs.hdparm}/sbin/hdparm -S 12 /dev/sda
  '';

  # torrent.wg-conf = "${myLib.secrets}/ru-torrent-wg.conf";
  sops.secrets.wg-conf = {
    sopsFile = "${myLib.secrets}/ru-torrent-wg.conf";
    format = "binary";
  };

  services.prometheus.node-exporter-docker.enable = true;
  services.printing.enable = false;

  services.tailscale = {
    enable = true;
    package = args.pkgs-unstable.tailscale;
    openFirewall = true;
  };

  # accept all incoming connections from tailscale
  networking.firewall.trustedInterfaces = ["tailscale0"];

  # Check btrfs automatically
  services.btrfs.autoScrub = {
    enable = true;
    interval = "*-*-01 03:00:00"; # monthly at 03 am
    fileSystems = [
      "/"
      "/mnt/hdd"
    ];
  };

  home-manager.users = {
    "ilma4" = import ./home.nix;
  };

  environment.pathsToLink = ["/share/zsh"];

  environment.systemPackages = with pkgs; [
    config.boot.kernelPackages.x86_energy_perf_policy
    hdparm
    resticprofile
    smartmontools
    vim # Do not forget to add an editor to edit configuration.nix! The Nano editor is also installed by default.
  ];

  services.smartd = {
    enable = true;
    extraOptions = [
      "--interval=86400" # run checks every 24 hours # TODO reset to default when switch to SSD
    ];
  };

  systemd.timers.restic-backup = {
    wantedBy = ["timers.target"];
    timerConfig = {
      OnCalendar = "*-*-* 00:04:00";
      Persistent = true;
    };
  };

  systemd.services.restic-backup = {
    path = [pkgs.resticprofile pkgs.restic];
    serviceConfig = {
      Type = "oneshot";
      ExecStart = "${pkgs.resticprofile}/bin/resticprofile -c \"${../../dotfiles/resticprofile/laat.toml}\" backup";
      User = "root";
    };
  };

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
