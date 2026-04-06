{
  config,
  lib,
  pkgs,
  ...
}: let
  inherit (lib) getExe mapAttrsToList mkEnableOption mkIf mkOption types;

  cfg = config.i4.backup;

  repoType = types.submodule {
    options = {
      location = mkOption {
        type = types.singleLineStr;
        description = "Restic repository location.";
      };
      passwordFile = mkOption {
        type = types.singleLineStr;
        description = "Path to the current repository password file.";
      };
      oldPasswordFile = mkOption {
        type = types.nullOr types.singleLineStr;
        default = null;
        description = "Path to the previous password file used for key rotation.";
      };
      extraResticArgs = mkOption {
        type = types.listOf types.str;
        default = [];
        description = "Extra global restic arguments added before the command.";
      };
      init = mkOption {
        type = types.bool;
        default = true;
        description = "Whether the module may initialize the repository when it does not exist.";
      };
    };
  };
in {
  options.i4.backup = {
    enable = mkEnableOption "local restic backups with remote copies";

    backupUser = mkOption {
      type = types.singleLineStr;
      default = "root";
      description = "User that runs the backup service.";
    };

    backupGroup = mkOption {
      type = types.singleLineStr;
      default = "root";
      description = "Group that runs the backup service.";
    };

    paths = mkOption {
      type = types.listOf types.str;
      default = [];
      description = "Paths that are backed up into the local repository.";
    };

    keepWithin = mkOption {
      type = types.nullOr types.singleLineStr;
      default = null;
      description = "Retention window passed to `restic forget --keep-within` for the local repository.";
    };

    time = mkOption {
      type = types.singleLineStr;
      default = "*-*-* 00:04:00";
      description = "systemd OnCalendar schedule for the periodic backup timer.";
    };

    localRepo = mkOption {
      type = repoType;
      description = "Local restic repository used for backups before snapshots are copied to remotes.";
    };

    remoteRepos = mkOption {
      type = types.attrsOf repoType;
      default = {};
      description = "Remote restic repositories that receive copies from the local repository.";
    };
  };

  config = mkIf cfg.enable (let
    backupConfigFile = pkgs.writeText "i4-backup-config.json" (builtins.toJSON {
      localRepo = cfg.localRepo;
      remoteRepos = mapAttrsToList (name: repo: repo // {inherit name;}) cfg.remoteRepos;
      paths = cfg.paths;
      keepWithin = cfg.keepWithin;
    });

    backupScript = pkgs.writers.writePython3Bin "i4-backup-run" {doCheck = false;} ''
      import sys

      sys.path.insert(0, ${builtins.toJSON (toString ./.)})

      from common import run_cli
      from run_backup import main

      if __name__ == "__main__":
          raise SystemExit(
              run_cli(
                  lambda: main(
                      ${builtins.toJSON (toString backupConfigFile)},
                      ${builtins.toJSON (getExe pkgs.restic)},
                  )
              )
          )
    '';
  in {
    assertions = [
      {
        assertion = cfg.localRepo != null;
        message = "i4.backup.localRepo must be configured when i4.backup.enable = true";
      }
      {
        assertion = cfg.paths != [];
        message = "i4.backup.paths must contain at least one path when i4.backup.enable = true";
      }
    ];

    systemd.services.i4-backup = {
      description = "Local restic backup with remote copies";
      after = ["network-online.target" "sops-nix.service"];
      wants = ["network-online.target"];
      serviceConfig = {
        Type = "oneshot";
        User = cfg.backupUser;
        Group = cfg.backupGroup;
        ExecStart = getExe backupScript;
      };
    };

    systemd.timers.i4-backup = {
      wantedBy = ["timers.target"];
      timerConfig = {
        OnCalendar = cfg.time;
        Persistent = true;
        Unit = "i4-backup.service";
      };
    };
  });
}
