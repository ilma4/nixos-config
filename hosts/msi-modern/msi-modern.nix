{
  inputs,
  pkgs,
  ...
}: {
  imports = let
    modules = ../../modules;
  in [
    inputs.home-manager.nixosModules.home-manager
    inputs.sops-nix.nixosModules.sops

    "${modules}/sops.nix"

    # Include the results of the hardware scan.
    ./hardware-configuration.nix
    ./llama.nix
  ];

  i4.swap.zswapEnable = true;
  i4.swap.swapEnable = true;

  i4.avahi.enable = true;
  i4.initrd-ssh.enable = true;
  i4.deploy.enable = true;

  # Prometheus node exporter: monitoring over Tailscale
  services.prometheus.exporters.node = {
    enable = true;
    openFirewall = true;
    firewallFilter = "-i tailscale0 -p tcp -m tcp --dport 9100";
  };

  # Use the systemd-boot EFI boot loader.
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  networking.hostName = "msi-modern"; # Define your hostname.

  boot.initrd.availableKernelModules = [
    "xhci_pci"

    # Replace with the driver reported by ethtool.
    "r8152"
  ];

  # DHCP for ethernet to usb adapters
  boot.initrd.systemd.network.networks."10-lan" = {
    matchConfig.Name = "en*";
    # "ipv4" to start dhcp client only on ipv4 and speed up the boot
    # "yes" will start two dhcp clients (both on ipv4 and ipv6) which works
    # but may be slower
    networkConfig.DHCP = "ipv4";
  };

  # Configure network connections interactively with nmcli or nmtui.
  networking.networkmanager.enable = true;

  # Select internationalisation properties.
  # i18n.defaultLocale = "en_US.UTF-8";
  # console = {
  #   font = "Lat2-Terminus16";
  #   keyMap = "us";
  #   useXkbConfig = true; # use xkb.options in tty.
  # };

  programs.sway.enable = true;

  xdg.portal = {
    enable = true;
    wlr.enable = true;
  };

  # Configure keymap in X11
  # services.xserver.xkb.layout = "us";
  # services.xserver.xkb.options = "eurosign:e,caps:escape";

  # Enable CUPS to print documents.
  # services.printing.enable = true;

  services.pipewire = {
    enable = true;
    pulse.enable = true;
  };

  # Enable touchpad support.
  services.libinput.enable = true;

  programs.firefox.enable = true;

  # List packages installed in system profile.
  # You can use https://search.nixos.org/ to find more packages (and options).
  environment.systemPackages = with pkgs; [
    vim # Do not forget to add an editor to edit configuration.nix! The Nano editor is also installed by default.
    wget
  ];

  home-manager.users = {
    "ilma4" = import ./home.nix;
  };

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
  system.stateVersion = "25.11"; # Did you read the comment?
}
