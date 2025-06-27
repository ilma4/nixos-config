args @ {
  config,
  pkgs,
  modules,
  ...
}: {
  imports = [
    ./hardware-configuration.nix
    ./hdd.nix

    "${modules}/base.nix"
    "${modules}/avahi.nix"
    "${modules}/zram.nix"
    "${modules}/sops.nix"
    # ./samba.nix

    "${modules}/server.nix"
    "${modules}/qbittorrent.nix"

    "${modules}/dashboard.nix"
    "${modules}/home-assistant.nix"
    "${modules}/pdf-tools.nix"

    "${modules}/actual-budget.nix"
    "${modules}/paperless.nix"

    "${modules}/immich.nix"
    "${modules}/syncthing.nix"

    "${modules}/grafana.nix"
  ];

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

  security.rtkit.enable = true; # realtime privileges

  networking.hostName = "ilma4-nas"; # Define your hostname.

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

  sops.age.keyFile = "/home/ilma4/.config/sops/age/keys.txt";
  sops.secrets."ssh/jb-mac/ilma4-nas/pub" = {
    owner = "ilma4";
    group = "users";
  };

  # suspend sata hdds after 1 minute of inactivity
  powerManagement.powerUpCommands = ''
    ${pkgs.hdparm}/sbin/hdparm -S 12 /dev/sdb
    ${pkgs.hdparm}/sbin/hdparm -S 12 /dev/sda
  '';

  torrent.wg-conf = "ru-torrent-wg.conf";

  # Enable background periodic TRIM
  services.fstrim.enable = true;

  # Enable CUPS to print documents.
  services.printing.enable = true;

  services.tailscale = {
    enable = true;
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

  # Define a user account. Don't forget to set a password with ‘passwd’.
  users.users.ilma4 = {
    isNormalUser = true;
    shell = pkgs.zsh;
    extraGroups = ["wheel"]; # Enable ‘sudo’ for the user.
    #openssh.authorizedKeys.keyFiles = [
    #  config.sops.secrets."/etc/ssh/jb-mac/ilma4-nas/pub".path
    #];
  };

  # Create .ssh/authorized_keys with right content
  systemd.tmpfiles.rules = let
    ilma4Home = config.users.users.ilma4.home;
  in [
    "d ${ilma4Home}/.ssh 0700 ilma4 users -"
    "L ${ilma4Home}/.ssh/authorized_keys - - - - ${config.sops.secrets."ssh/jb-mac/ilma4-nas/pub".path}"
  ];

  home-manager.users = {
    "ilma4" = import ./home.nix;
  };

  services.swapspace.enable = true; # auto swap files when needed

  programs.zsh.enable = true; # configured via home-manager
  environment.pathsToLink = ["/share/zsh"];

  environment.systemPackages = with pkgs; [
    config.boot.kernelPackages.x86_energy_perf_policy
    hdparm
    smartmontools
    vim # Do not forget to add an editor to edit configuration.nix! The Nano editor is also installed by default.
  ];

  # Enable the OpenSSH daemon.
  services.openssh = {
    enable = true;
    openFirewall = true;
    settings.PasswordAuthentication = false;
  };

  services.smartd = {
    enable = true;
    extraOptions = [
      "--interval=10800" # run checks every 3 hours # TODO reset to default when noise wont be issue
    ];
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
