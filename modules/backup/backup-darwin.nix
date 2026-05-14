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
    mkAfter
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
    system.activationScripts.extraActivation.text = mkAfter ''
      set -euo pipefail

      mkdir -p ${escapeShellArg cfg.localRepo.location}
      chown ${escapeShellArg "${cfg.backupUser}:${cfg.backupGroup}"} ${escapeShellArg cfg.localRepo.location}
      chmod 0750 ${escapeShellArg cfg.localRepo.location}

      touch /tmp/i4-backup.log
      chown ${escapeShellArg "${cfg.backupUser}:${cfg.backupGroup}"} /tmp/i4-backup.log
      chmod 0644 /tmp/i4-backup.log
    '';

    launchd.user.agents.i4-backup = {
      path = [pkgs.restic];
      serviceConfig = {
        ProgramArguments = ["/bin/bash" "${backupDriverScript}"];
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
