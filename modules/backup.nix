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
