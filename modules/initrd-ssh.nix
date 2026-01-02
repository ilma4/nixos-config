{
  config,
  lib,
  ...
}: let
  cfg = config.i4.initrd-ssh;
in {
  config = lib.mkIf cfg.enable {
    boot.initrd.systemd.enable = lib.mkDefault true;
    boot.initrd.network.enable = lib.mkDefault true;

    boot.initrd.network.ssh = {
      enable = lib.mkDefault true;

      # Keep defaults aligned with previous `hosts/laat/laat.nix` setup.
      hostKeys = lib.mkDefault ["/etc/secrets/initrd/ssh_host_ed25519_key"];

      authorizedKeys = lib.mkDefault [
        config.i4.my-ssh-key.publicKey
      ];
    };
  };
}
