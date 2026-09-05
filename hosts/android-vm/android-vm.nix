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

  nix.settings.experimental-features = [
    "nix-command"
    "flakes"
  ];

  boot.loader.grub = {
    device = "nodev";
    efiSupport = true;
    efiInstallAsRemovable = true;
  };

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
