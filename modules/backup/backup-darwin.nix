{
  config,
  lib,
  myLib,
  pkgs,
  ...
}: let
  inherit
    (lib)
    escapeShellArg
    mkIf
    ;

  cfg = config.i4.backup;

  backupDriverScript = pkgs.writeShellScript "i4-backup-driver" ''
    set -euo pipefail

    ${cfg.internal.initReposScript}
    ${cfg.internal.rotateKeysScript}
    ${cfg.internal.runBackupScript}
  '';
in {
  config = myLib.unifiedModules.enableForConfigurations ["isDarwin"] (mkIf cfg.enable {
    system.activationScripts.i4-backup-local-repo.text = ''
      set -euo pipefail

      mkdir -p ${escapeShellArg cfg.localRepo.location}
      chown ${escapeShellArg "${cfg.backupUser}:${cfg.backupGroup}"} ${escapeShellArg cfg.localRepo.location}
      chmod 0750 ${escapeShellArg cfg.localRepo.location}
    '';

    launchd.daemons.i4-backup = {
      path = [pkgs.restic];
      serviceConfig = {
        UserName = cfg.backupUser;
        GroupName = cfg.backupGroup;
        ProgramArguments = ["${backupDriverScript}"];
        StandardOutPath = "/tmp/i4-backup.log";
        StandardErrorPath = "/tmp/i4-backup.log";
        StartCalendarInterval = [
          {
            Hour = cfg.backupHour;
            Minute = cfg.backupMinute;
          }
        ];
      };
    };
  });
}
