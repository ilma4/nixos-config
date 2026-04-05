{
  config,
  lib,
  constants,
  ...
}: let
  cfg = config.i4.initrd-ssh;
  keyPath = "/etc/secrets/initrd/ssh_host_ed25519_key";
in {
  config = lib.mkIf cfg.enable {
    boot.initrd.systemd.enable = lib.mkDefault true;
    boot.initrd.network.enable = lib.mkDefault true;

    boot.initrd.network.ssh = {
      enable = lib.mkDefault true;

      # Keep defaults aligned with previous `hosts/nas/nas.nix` setup.
      hostKeys = lib.mkDefault [keyPath];

      authorizedKeys = lib.mkDefault constants.main-pub-keys;
    };
  };
}
