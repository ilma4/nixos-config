{
  config,
  lib,
  modulesPath,
  pkgs,
  ...
}: {
  imports = [
    (modulesPath + "/profiles/qemu-guest.nix")
  ];

  networking.hostName = "android-vm";

  services.lima.enable = true;
  services.openssh.enable = true;

  users.mutableUsers = true;
  security.sudo.wheelNeedsPassword = false;

  nix.settings.experimental-features = [
    "nix-command"
    "flakes"
  ];

  boot.loader.grub.enable = false;
  boot.loader.systemd-boot.enable = true;
  boot.loader.systemd-boot.configurationLimit = 1;

  fileSystems."/boot" = {
    device = lib.mkForce "/dev/vda1";
    fsType = "vfat";
  };

  fileSystems."/" = {
    device = "/dev/disk/by-label/nixos";
    fsType = "ext4";
    autoResize = true;
    options = ["noatime"];
  };

  boot.kernelPackages = pkgs.linux-asahi;

  environment.systemPackages = with pkgs; [
    git
    gitRepo
    ccache
    python3
    rsync
    unzip
    zip
    curl
  ];

  system.stateVersion = "26.05";
}
