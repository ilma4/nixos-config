{
  config,
  lib,
  myLib,
  pkgs,
  ...
}: let
  inherit
    (lib)
    fixedWidthNumber
    mkIf
    ;

  cfg = config.i4.backup;
  internal = cfg.internal;

  commonAfter = ["network-online.target" "sops-nix.service"];
  tmpfilesSetupService = "systemd-tmpfiles-setup.service";
  backupCalendar = "*-*-* ${fixedWidthNumber 2 cfg.backupHour}:${fixedWidthNumber 2 cfg.backupMinute}:00";

  mkBackupService = description: execStart: extraConfig:
    {
      inherit description;
      after = commonAfter;
      wants = ["network-online.target"];
      path = [pkgs.restic];
      serviceConfig = {
        Type = "oneshot";
        User = cfg.backupUser;
        Group = cfg.backupGroup;
        ExecStart = execStart;
      };
    }
    // extraConfig;
in {
  config = myLib.unifiedModules.enableForConfigurations ["isNixos"] (mkIf cfg.enable {
    systemd.tmpfiles.rules = [
      "d ${cfg.localRepo.location} 0750 ${cfg.backupUser} ${cfg.backupGroup} -"
    ];

    systemd.services = {
      i4-backup-init-local = mkBackupService "Initialize local restic backup repository" internal.initReposScript {
        after = commonAfter ++ [tmpfilesSetupService];
        requires = [tmpfilesSetupService];
      };

      i4-backup-rotate-keys = mkBackupService "Rotate restic repository keys" internal.rotateKeysScript {
        after = commonAfter ++ ["i4-backup-init-local.service"];
        requires = ["i4-backup-init-local.service"];
      };

      i4-backup = mkBackupService "Run local restic backup, remote copy, and retention" internal.runBackupScript {
        after = commonAfter ++ ["i4-backup-rotate-keys.service"];
        requires = ["i4-backup-rotate-keys.service"];
      };
    };

    systemd.timers.i4-backup = {
      wantedBy = ["timers.target"];
      timerConfig = {
        OnCalendar = backupCalendar;
        Persistent = true;
        Unit = "i4-backup.service";
      };
    };
  });
}
