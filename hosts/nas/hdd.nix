{...}: {
  fileSystems."/mnt/hdd" = {
    device = "/dev/disk/by-uuid/f86b7490-3309-44ad-876a-50a8578012b0";
    fsType = "btrfs";
    options = [
      "compress=zstd"
      "nofail" # allow system too boot if mount fails
      "x-systemd.idle-timeout=1min"
      "x-systemd.automount"
    ];
  };

  # create mountpoints for hdd
  systemd.tmpfiles.rules = [
    "d /mnt 0755 root root"
    "d /mnt/hdd 0755 root root"
  ];
}
