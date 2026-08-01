{
  config,
  lib,
  pkgs,
  constants,
  ...
}: let
  # Both the SSD staging repository and existing HDD repository are owned by
  # ilma4, so the relay can copy between them directly.
  backupUser = "ilma4";
  backupGroup = config.users.users.${backupUser}.group;
  # /var/lib is on the NAS root SSD; /mnt/hdd remains the durable local copy.
  backupHome = "/var/lib/quicksilver-backup";
  backupSsdRepo = "${backupHome}/restic";
  backupCache = "${backupHome}/restic-cache";
  backupKnownHosts = "${backupHome}/known_hosts";

  nasToHetzerKey = constants.backup-ssh-keys.nas-to-hetzer-storage;

  quicksilverResticPasswordSecret = "restic_password/quicksilver_local";
  nasResticPasswordSecret = constants.nas.restic-ilma4.password-secret;
  hetzerResticPasswordSecret = constants.hetzer-restic.password-secret;

  ssdAppendOnlyResticCommand = pkgs.writeShellScript "i4-quicksilver-ssd-restic-append-only" ''
    set -euo pipefail

    umask 077
    exec ${lib.getExe pkgs.rclone} serve restic --stdio --append-only ${lib.escapeShellArg backupSsdRepo}
  '';
  hetzerStorageBoxRcloneProgram = "${lib.getExe pkgs.openssh} -F /dev/null -i ${config.sops.secrets.${nasToHetzerKey.private-secret}.path} -o BatchMode=yes -o IdentitiesOnly=yes -o StrictHostKeyChecking=accept-new -o UserKnownHostsFile=${backupKnownHosts} -p 23 u478838@u478838.your-storagebox.de rclone";

  mkRepo = {
    location,
    passwordFile,
    oldPasswordFile ? null,
    extraArgs ? [],
  }: {
    inherit location passwordFile oldPasswordFile extraArgs;
  };

  ssdRepo = mkRepo {
    location = backupSsdRepo;
    passwordFile = config.sops.secrets.${quicksilverResticPasswordSecret}.path;
  };
  hddRepo = mkRepo {
    location = constants.nas.restic-ilma4.location;
    passwordFile = config.sops.secrets.${nasResticPasswordSecret}.path;
  };
  hetzerRepo = mkRepo {
    location = "rclone:${constants.hetzer-restic.repo}";
    passwordFile = config.sops.secrets.${hetzerResticPasswordSecret}.path;
    extraArgs = [
      "-o"
      "rclone.program=${hetzerStorageBoxRcloneProgram}"
      "-o"
      "rclone.args=serve restic --stdio --append-only"
    ];
  };

  initConfig = pkgs.writeText "i4-quicksilver-backup-init.json" (builtins.toJSON [
    ssdRepo
    hddRepo
  ]);
  rotateKeysConfig = pkgs.writeText "i4-quicksilver-backup-rotate-keys.json" (builtins.toJSON [
    ssdRepo
    hddRepo
    hetzerRepo
  ]);
  relayConfig = pkgs.writeText "i4-quicksilver-backup-relay.json" (builtins.toJSON {
    localRepo = ssdRepo;
    remoteRepos = [hddRepo hetzerRepo];
    createSnapshots = false;
    paths = [];
    excludes = [];
    keepWithin = "7d";
  });

  backupProgram = config.i4.backup.internal.backupProgram;
  probeSsdRepoCommand = lib.escapeShellArgs [
    (lib.getExe pkgs.restic)
    "-r"
    ssdRepo.location
    "--password-file"
    ssdRepo.passwordFile
    "cat"
    "config"
  ];
  initScript = pkgs.writeShellScript "i4-quicksilver-backup-init" ''
    set -euo pipefail

    # Avoid waking the HDD after the SSD repository has been initialized.
    if ${probeSsdRepoCommand} >/dev/null 2>&1; then
      exit 0
    fi

    exec ${lib.escapeShellArgs [backupProgram "init-repos" (toString initConfig)]}
  '';
  rotateKeysScript = pkgs.writeShellScript "i4-quicksilver-backup-rotate-keys" ''
    set -euo pipefail

    exec ${lib.escapeShellArgs [backupProgram "rotate-keys" (toString rotateKeysConfig)]}
  '';
  relayScript = pkgs.writeShellScript "i4-quicksilver-backup-relay" ''
    set -euo pipefail

    exec ${lib.escapeShellArgs [backupProgram "run-backup" (toString relayConfig)]}
  '';

  commonAfter = ["local-fs.target" "network-online.target" "sops-nix.service"];
  mkBackupService = description: execStart: extraConfig:
    lib.recursiveUpdate {
      inherit description;
      after = commonAfter;
      wants = ["network-online.target"];
      path = [pkgs.restic];
      environment = {
        HOME = backupHome;
        RESTIC_CACHE_DIR = backupCache;
      };
      serviceConfig = {
        Type = "oneshot";
        User = backupUser;
        Group = backupGroup;
        WorkingDirectory = backupHome;
        UMask = "0007";
        ExecStart = execStart;
      };
    }
    extraConfig;
in {
  users.users.${backupUser}.openssh.authorizedKeys.keys = [
    ''command="${ssdAppendOnlyResticCommand}",no-agent-forwarding,no-port-forwarding,no-X11-forwarding,no-pty,no-user-rc ${constants.quicksilver.backup-pub-key}''
  ];

  sops.secrets.${nasToHetzerKey.private-secret} = {
    owner = backupUser;
    group = backupGroup;
    mode = "0400";
  };
  sops.secrets.${quicksilverResticPasswordSecret} = {
    owner = backupUser;
    group = backupGroup;
    mode = "0400";
  };
  sops.secrets.${nasResticPasswordSecret} = {
    owner = backupUser;
    group = backupGroup;
    mode = "0400";
  };
  sops.secrets.${hetzerResticPasswordSecret} = {
    owner = backupUser;
    group = backupGroup;
    mode = "0400";
  };

  systemd.tmpfiles.rules = [
    "d ${backupHome} 0700 ${backupUser} ${backupGroup} -"
    "d ${backupSsdRepo} 0700 ${backupUser} ${backupGroup} -"
    "d ${backupCache} 0700 ${backupUser} ${backupGroup} -"
    "f ${backupKnownHosts} 0600 ${backupUser} ${backupGroup} -"
  ];

  systemd.services = {
    i4-quicksilver-backup-init = mkBackupService "Initialize the Quicksilver SSD relay repository" initScript {
      wantedBy = ["multi-user.target"];
      after = commonAfter ++ ["systemd-tmpfiles-setup.service"];
      requires = ["systemd-tmpfiles-setup.service"];
      serviceConfig.RemainAfterExit = true;
    };

    i4-quicksilver-backup-rotate-keys = mkBackupService "Rotate Quicksilver relay repository keys" rotateKeysScript {
      after = commonAfter ++ ["i4-quicksilver-backup-init.service"];
      requires = ["i4-quicksilver-backup-init.service"];
    };

    i4-quicksilver-backup-relay = mkBackupService "Copy Quicksilver snapshots from SSD to HDD and Hetzer" relayScript {
      after = commonAfter ++ ["i4-quicksilver-backup-rotate-keys.service"];
      requires = ["i4-quicksilver-backup-rotate-keys.service"];
    };
  };

  systemd.timers.i4-quicksilver-backup-relay = {
    description = "Relay Quicksilver snapshots from NAS SSD";
    wantedBy = ["timers.target"];
    timerConfig = {
      OnCalendar = "*-*-* 05:00:00";
      Persistent = true;
      Unit = "i4-quicksilver-backup-relay.service";
    };
  };
}
