{...}: {
  # Created with mkfs.btrfs --checksum xxhash; checksums are a format-time setting.
  fileSystems."/mnt/ssd" = {
    device = "/dev/disk/by-uuid/2bc565c4-0317-4327-81e1-22a8f211f681";
    fsType = "btrfs";
    options = [
      "compress=zstd:3"
      "noatime"
      "nofail"
      "x-systemd.automount"
    ];
  };
}
