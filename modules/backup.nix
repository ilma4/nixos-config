{
  config,
  lib,
  pkgs,
  ...
}: {
  config = {
    users.users.backup = {
      isSystemUser = true;
      group = "actual-budget";
    };
    users.groups.backup = {};

    systemd.tmpfiles.rules = let
      backup-user = config.users.users.backup;
      backup-group = config.users.groups.backup;
    in [
      "d /var/restic 0750 ${backup-user} ${backup-group} -"
    ];
  };
}
