#Edit this configuration file to define what should be installed on
# your system. Help is available in the configuration.nix(5) man page, on
# https://search.nixos.org/options and in the NixOS manual (`nixos-help`).
{
  config,
  lib,
  pkgs,
  inputs,
  modules,
  ...
}: {
  imports = [
    ./hardware-configuration.nix
    "${modules}/zram.nix"
    "${modules}/nix-settings.nix"
    ./samba.nix

    #./server.nix
    #./immich.nix
    #./paperless.nix
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

  #nix.settings.experimental-features = ["nix-command" "flakes"]; hardware.enableAllFirmware = true;
  security.rtkit.enable = true; # realtime privileges

  networking.hostName = "ilma4-nas"; # Define your hostname.
  # Pick only one of the below networking options.
  # networking.wireless.enable = true;  # Enables wireless support via wpa_supplicant.
  # networking.networkmanager.enable = true; # Easiest to use and most distros use this by default.

  boot.initrd.systemd.enable = true;
  boot.initrd.network.enable = true;

  boot.initrd.network.ssh = {
    enable = true;
    hostKeys = [ "/etc/secrets/initrd/ssh_host_ed25519_key" ];
    authorizedKeys = [ "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIM4gqAl3ZqveXhNkOrOb6tv9EBbSfV3RlvvP778PzAyN ilma4@DE-UNIT-1832" ];
    # authorizedKeyFiles = [ config.sops.secrets.ssh-jb-mac-to-ilma4-pub.path ];
  };



  # Set your time zone.
  time.timeZone = "Europe/Amsterdam";

  # Configure network proxy if necessary
  # networking.proxy.default = "http://user:password@proxy:port/";
  # networking.proxy.noProxy = "127.0.0.1,localhost,internal.domain";

  # Select internationalisation properties.
  i18n.defaultLocale = "en_US.UTF-8";
  # console = {
  #   font = "Lat2-Terminus16";
  #   keyMap = "us";
  #   useXkbConfig = true; # use xkb.options in tty.
  # };

  # Enable background periodic TRIM
  services.fstrim.enable = true;

  # Enable avahi server. Machine will be avaliable by address 'hostname'
  /*
  services.avahi = {
    enable = true;
    reflector = true;
    nssmdns4 = true; # enables .local resolution
  };
  */

  # Enable CUPS to print documents.
  services.printing.enable = true;

  services.tailscale = {
    enable = true;
    openFirewall = true;
  };

  # accept all incoming connections from tailscale
  networking.firewall.trustedInterfaces = [ "tailscale0" ];

  # Check btrfs automatically
  services.btrfs.autoScrub = {
    enable = true;
    interval = "*-*-01 03:00:00"; # monthly at 03 am
    fileSystems = [
      "/" 
      "/mnt/hdd"
      "/mnt/ssd256"
    ];
  };

  # Define a user account. Don't forget to set a password with ‘passwd’.
  users.users.ilma4 = {
    isNormalUser = true;
    shell = pkgs.zsh;
    extraGroups = ["wheel"]; # Enable ‘sudo’ for the user.
  };

  home-manager.users = {
    "ilma4" = import ./home.nix;
  };

  services.swapspace.enable = true; # auto swap files when needed

  # List packages installed in system profile. To search, run:
  programs.screen.enable = true;

  programs.zsh.enable = true; # configured via home-manager
  environment.pathsToLink = ["/share/zsh"];

  # $ nix search wget
  environment.systemPackages = with pkgs; [
    vim # Do not forget to add an editor to edit configuration.nix! The Nano editor is also installed by default.
  ];

  # Some programs need SUID wrappers, can be configured further or are
  # started in user sessions.
  # programs.mtr.enable = true;
  # programs.gnupg.agent = {
  #   enable = true;
  #   enableSSHSupport = true;
  # };

  # List services that you want to enable:

  # Enable the OpenSSH daemon.
  services.openssh = {
    enable = true;
    openFirewall = true;
    # settings.PasswordAuthentication = false; # TODO set false
  };

  services.smartd = {
    enable = true;
    #autodetect = false;
    # TODO add all disks
    
    #devices = [
    #  {device = "/dev/nvme0n1";}
    #  {device = "/dev/disk/by-uuid/b043e463-7643-47a9-8c9e-66a013a714a8";}
    #];
    # defaults.autodetected = "-a -o on -S on -n standby,q -s (S/../.././02|L/../../7/04)" ;
  };

  # programs.nix-ld.enable = true;

  # Open ports in the firewall.
  # networking.firewall.allowedTCPPorts = [ ... ];
  # networking.firewall.allowedUDPPorts = [ ... ];
  # Or disable the firewall altogether.
  # networking.firewall.enable = false;

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
