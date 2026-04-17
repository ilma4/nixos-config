{
  config,
  lib,
  myLib,
  pkgs,
  ...
}: let
  inherit
    (lib)
    escapeShellArgs
    getExe
    mapAttrsToList
    mkEnableOption
    mkIf
    mkMerge
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

  mkBackupScript = name: command: configFile:
    pkgs.writeShellScript name ''
      exec ${escapeShellArgs [(getExe backupScript) command configFile]}
    '';

  initReposScript = mkBackupScript "i4-backup-init-repos" "init-repos" initReposConfigFile;
  rotateKeysScript = mkBackupScript "i4-backup-rotate-keys" "rotate-keys" rotateKeysConfigFile;
  runBackupScript = mkBackupScript "i4-backup-run-backup" "run-backup" runBackupConfigFile;
in {
  imports = [
    ./restic-wrappers.nix
    ./metrics.nix
    ./backup-nixos.nix
    ./backup-darwin.nix
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

    backupHour = mkOption {
      type = types.ints.between 0 23;
      default = 4;
      description = "Hour of day in local time when the periodic backup runs.";
    };

    backupMinute = mkOption {
      type = types.ints.between 0 59;
      default = 0;
      description = "Minute of the hour in local time when the periodic backup runs.";
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

    localRepo = mkOption {
      type = repoType;
      description = "Local restic repository used for backups before snapshots are copied to remotes.";
    };

    remoteRepos = mkOption {
      type = types.attrsOf repoType;
      default = {};
      description = "Remote restic repositories that receive copies from the local repository.";
    };

    internal = {
      initReposScript = mkOption {
        type = types.path;
        readOnly = true;
        description = "Generated script that initializes the configured restic repositories.";
      };

      rotateKeysScript = mkOption {
        type = types.path;
        readOnly = true;
        description = "Generated script that rotates restic repository keys.";
      };

      runBackupScript = mkOption {
        type = types.path;
        readOnly = true;
        description = "Generated script that runs the local backup, remote copy, and retention steps.";
      };
    };
  };

  config = mkMerge [
    (mkIf cfg.enable {
      i4.backup.internal = {
        inherit
          initReposScript
          rotateKeysScript
          runBackupScript
          ;
      };

      assertions = [
        {
          assertion = cfg.paths != [];
          message = "i4.backup.paths must contain at least one path when i4.backup.enable = true";
        }
      ];
    })
  ];
}
