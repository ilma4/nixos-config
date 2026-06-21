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

      # With UsePAM disabled (default in initrd), sshd prints /etc/motd
      # itself right before dropping to the shell. `lines` type, so this
      # concatenates with any host-specific extraConfig instead of clobbering it.
      extraConfig = "PrintMotd yes\n";
    };

    # Shown to anyone who SSHes into the initrd, printed by sshd (PrintMotd)
    # just before the interactive shell starts.
    boot.initrd.systemd.contents."/etc/motd".text = ''
      run systemd-tty-ask-password-agent to unlock encrypted drive
    '';
  };
}
