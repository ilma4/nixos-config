{
  config,
  lib,
  pkgs,
  ...
}: let
  inherit
    (lib)
    concatMapStringsSep
    escapeShellArgs
    getExe
    hasPrefix
    mapAttrsToList
    mkEnableOption
    mkIf
    mkOption
    types
    ;

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
    };
  };
in {
  imports = [
    ./restic-wrappers.nix
    ./metrics.nix
  ];

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
    commonAfter = ["network-online.target" "sops-nix.service"];
    tmpfilesSetupService = "systemd-tmpfiles-setup.service";

    translateRepo = repo: {
      inherit (repo) location passwordFile oldPasswordFile;
      extraArgs = repo.extraResticArgs;
    };

    remoteRepos = mapAttrsToList (_: repo: repo) cfg.remoteRepos;
    allRepos = [cfg.localRepo] ++ remoteRepos;

    runBackupConfigFile = pkgs.writeText "i4-backup-run-backup.json" (builtins.toJSON {
      localRepo = translateRepo cfg.localRepo;
      remoteRepos = map translateRepo remoteRepos;
      paths = cfg.paths;
      keepWithin = cfg.keepWithin;
    });

    rotateKeysConfigFile = pkgs.writeText "i4-backup-rotate-keys.json" (builtins.toJSON (
      map translateRepo allRepos
    ));

    initReposConfigFile = pkgs.writeText "i4-backup-init-repos.json" (builtins.toJSON (
      map translateRepo allRepos
    ));

    backupScript = pkgs.writers.writeHaskellBin "i4-backup" {
      libraries = with pkgs.haskellPackages; [aeson bytestring containers process];
    } (builtins.readFile ./backup.hs);

    mkBackupCommand = command: configFile: "${getExe backupScript} ${command} ${configFile}";

    initReposCommand = pkgs.writeShellScript "i4-backup-init-repos" ''
      exec ${mkBackupCommand "init-repos" initReposConfigFile}
    '';

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
    assertions = [
      {
        assertion = cfg.localRepo != null;
        message = "i4.backup.localRepo must be configured when i4.backup.enable = true";
      }
      {
        assertion = cfg.paths != [];
        message = "i4.backup.paths must contain at least one path when i4.backup.enable = true";
      }
      {
        assertion = cfg.localRepo == null || hasPrefix "/" cfg.localRepo.location;
        message = "i4.backup.localRepo.location must be an absolute path when i4.backup.enable = true";
      }
    ];

    systemd.tmpfiles.rules = [
      "d ${cfg.localRepo.location} 0750 ${cfg.backupUser} ${cfg.backupGroup} -"
    ];

    systemd.services = {
      i4-backup-init-local = mkBackupService "Initialize local restic backup repository" initReposCommand {
        after = commonAfter ++ [tmpfilesSetupService];
        requires = [tmpfilesSetupService];
      };

      i4-backup-rotate-keys = mkBackupService "Rotate restic repository keys" (mkBackupCommand "rotate-keys" rotateKeysConfigFile) {
        after = commonAfter ++ ["i4-backup-init-local.service"];
        requires = ["i4-backup-init-local.service"];
      };

      i4-backup = mkBackupService "Run local restic backup, remote copy, and retention" (mkBackupCommand "run-backup" runBackupConfigFile) {
        after = commonAfter ++ ["i4-backup-rotate-keys.service"];
        requires = ["i4-backup-rotate-keys.service"];
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
