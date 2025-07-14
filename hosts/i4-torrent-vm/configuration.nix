{
  config,
  lib,
  pkgs,
  flake-location,
  ...
}: {
  imports = [
    ./hardware-configuration.nix
    "${flake-location}/modules/base.nix"
    "${flake-location}/modules/avahi.nix"
    "${flake-location}/modules/sops.nix"
    "${flake-location}/modules/qbittorrent.nix"
  ];

  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  networking.hostName = "i4-torrent-vm"; # Define your hostname.

  users.users.ilma4 = {
    isNormalUser = true;
    extraGroups = ["wheel"]; # Enable ‘sudo’ for the user.
  };

  torrent.wg-conf = "ru-torrent-nixos-vm-wg.conf";
  virtualisation.oci-containers.containers.qbittorrent.autoStart = true;

  environment.systemPackages = with pkgs; [
    neovim
  ];

  services.tailscale = {
    enable = true;
    openFirewall = true;
  };

  # accept all incoming connections from tailscale
  networking.firewall.trustedInterfaces = ["tailscale0"];

  services.qemuGuest.enable = true;
  services.openssh.enable = true;

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
  system.stateVersion = "24.11"; # Did you read the comment?
}
