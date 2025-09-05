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

    systemd.tmpfiles.rules = ''
      d /persist/restic 0750 backup backup - -
    '';
  };
}
