{
  config,
  constants,
  lib,
  pkgs,
  ...
}: let
  user = "ilma4";
  inherit (config.users.users.${user}) home group;
  statusDirectory = "/var/lib/i4-backup-metrics";
  nasHost = "nas.tail09544e.ts.net";
  inherit (constants.quicksilver) backup-password-secret backup-private-secret;
  secretPermissions = {
    owner = user;
    inherit group;
    mode = "0400";
  };
  nasRcloneProgram = lib.escapeShellArgs [
    (lib.getExe pkgs.openssh)
    "-F"
    "/dev/null"
    "-i"
    config.sops.secrets.${backup-private-secret}.path
    "-oBatchMode=yes"
    "-oIdentitiesOnly=yes"
    "-oConnectTimeout=15"
    "-oStrictHostKeyChecking=yes"
    "-oUserKnownHostsFile=/dev/null"
    "${user}@${nasHost}"
  ];
in {
  imports = [../../modules/backup/backup.nix];

  i4.sops.enable = true;
  sops.secrets.${backup-password-secret} = secretPermissions;
  sops.secrets.${backup-private-secret} = secretPermissions;

  programs.ssh.knownHosts.${nasHost}.publicKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIA3lID2CiaqCRMV4DhOQbAAftwO8NbCJqiLbRSm9qbtc";

  i4.backup = {
    enable = true;
    backupUser = user;
    backupGroup = group;
    # Use the shared module's daily 04:00 schedule with seven days locally.
    paths = [home];
    excludes = map (path: "${home}/${path}") [
      "Downloads"
      "Games"
      "NoBackup"
      ".cache"
      ".local/share/Trash"
      ".local/share/Steam"
      ".local/share/PrismLauncher"
      ".local/share/containers"
      ".local/share/flatpak"
      ".local/share/junie"
      ".local/share/zed"
      ".local/share/TelegramDesktop/tdata/user_data/media_cache"
      ".config/**/Cache"
      ".config/**/Code Cache"
      ".config/**/GPUCache"
      ".thunderbird/*/ImapMail"
      ".android/avd"
      ".cargo/registry"
      ".cargo/git"
      ".npm/_cacache"
      ".ollama/models"
      ".pi/agent/npm/node_modules"
    ];
    keepWithin = "7d";
    localRepo = {
      location = "${home}/NoBackup/restic";
      passwordFile = config.sops.secrets.${backup-password-secret}.path;
    };
    # The existing NAS relay copies all snapshots, including msi-modern's.
    remoteRepos.nas-ssd = {
      inherit (config.i4.backup.localRepo) passwordFile;
      location = "rclone:nas-ssd";
      extraResticArgs = [
        "--retry-lock"
        "10m"
        "-o"
        "rclone.program=${nasRcloneProgram}"
        "-o"
        "rclone.args=serve restic --stdio"
      ];
    };
    statusMetrics = {
      file = "${statusDirectory}/backup.prom";
      source = "msi-modern";
    };
  };

  systemd.timers.i4-backup.timerConfig.WakeSystem = true;
  systemd.tmpfiles.rules = [
    "d ${statusDirectory} 0755 ${user} ${group} -"
  ];
  services.prometheus.exporters.node.extraFlags = ["--collector.textfile.directory=${statusDirectory}"];
}
