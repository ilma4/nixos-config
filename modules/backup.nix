{
  config,
  lib,
  pkgs,
  ...
}: {
  config = {
    users.users.backup = {
      isSystemUser = true;
      group = config.users.groups.backup.name;
      shell = pkgs.bash;
      openssh.authorizedKeys.keys = [
        "restrict,command=\"${pkgs.rclone}/bin/rclone serve restic --stdio --append-only --b2-hard-delete /var/restic\",no-pty,no-agent-forwarding,no-port-forwarding,no-X11-forwarding ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIGlG8sgxuAVYsgfcrJOXnoIVm8h/UYPPOCljmkpaiG+2 backup-key"
      ];
    };
    users.groups.backup = {};

    systemd.tmpfiles.rules = let
      backup-user = config.users.users.backup.name;
      backup-group = config.users.groups.backup.name;
    in [
      "d /var/restic 0750 ${backup-user} ${backup-group} -"
    ];
  };
}
