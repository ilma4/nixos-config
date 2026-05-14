{
  config,
  lib,
  pkgs,
  ...
}: let
  backupHome = "/Users/backup";
  backupCache = "${backupHome}/cache";
  backupLocalRepo = "${backupHome}/repo";
  localResticPasswordSecret = "restic_password/quicksilver_local";
  remoteResticPasswordSecret = "restic_password/ilma4_legacy";
  backupSshKey = config.sops.secrets."quicksilver-backup-key".path;
  rcloneProgram = "${lib.getExe pkgs.openssh} -F /dev/null -i ${backupSshKey} -o IdentitiesOnly=yes -o StrictHostKeyChecking=accept-new -o UserKnownHostsFile=${backupHome}/.ssh/known_hosts ilma4@nas.local";
  backupExcludePaths = [
    "/Users/ilma4/Games"
    "/Users/ilma4/Library/Application Support/Steam"
    "/Users/ilma4/Library/Application Support/PrismLauncher"
    "/Users/ilma4/Downloads"
    "/Users/ilma4/NoBackup"
    "/Users/ilma4/.cache"
    "/Users/ilma4/.Trash"
    "/Users/ilma4/Library/Caches"
    "/Users/ilma4/Library/Android"
    "/Users/ilma4/Library/Developer"
    "/Users/ilma4/Library/Containers"
    "/Users/ilma4/Library/Java"
    "/Users/ilma4/Library/Logs"
    "/Users/ilma4/Library/Thunderbird/Profiles/*/ImapMail"
    "/Users/ilma4/Library/Application Support/JetBrains"
    "/Users/ilma4/Library/Application Support/com.apple.container"
    "/Users/ilma4/Library/Application Support/JetBrains/*/plugins"
    "/Users/ilma4/Library/Application Support/Google"
    "/Users/ilma4/Library/Application Support/Slack"
    "/Users/ilma4/Library/Application Support/Zed"
    "/Users/ilma4/Library/Application Support/*/Cache"
    "/Users/ilma4/Library/Application Support/*/Code Cache"
    "/Users/ilma4/IdeaProjects"
    "/Users/ilma4/Library/Application Support/Code/CachedExtensionVSIXs"
    "/Users/ilma4/Library/Application Support/Vivaldi/*/File System"
    "/Users/ilma4/Library/DuetExpertCenter"
    "/Users/ilma4/Library/Metadata/CoreSpotlight"
    "/Users/ilma4/Library/Daemon Containers/*/Data/com.apple.milod"
    "/Users/ilma4/Library/Biome/streams/restricted/Safari.PageLoad"
    "/Users/ilma4/Library/Application Support/FileProvider"
    "/Users/ilma4/Library/Group Containers/group.com.apple.secure-control-center-preferences"
    "/Users/ilma4/Library/Group Containers/*.groups.com.apple.podcasts"
    "/Users/ilma4/Library/Application Support/MobileSync"
    "/Users/ilma4/Library/Group Containers/*.group.com.apple.configurator"
    "/Users/ilma4/Google Drive"
    "/Users/ilma4/Library/CloudStorage"
    "/Users/ilma4/Virtual Machines.localized"
    "/Users/ilma4/Projects/JetBrains"
    "/Users/ilma4/JetBrains"
    "/Users/ilma4/*/AeroSpace/.build"
    "/Users/ilma4/Projects/tdesktop"
    "/Users/ilma4/Projects/telegram"
    "/Users/ilma4/Projects/Telegram-Android"
    "/Users/ilma4/Projects/Nekogram"
    "/Users/ilma4/.android"
    "/Users/ilma4/.colima"
    "/Users/ilma4/.local/share"
    "/Users/ilma4/.vscode"
    "/Users/ilma4/.ollama"
    "/Users/ilma4/.lmstudio"
    "/Users/ilma4/.gemini"
    "/Users/ilma4/.junie"
    "/Users/ilma4/.konan"
    "/Users/ilma4/.lldb"
    "/Users/ilma4/.npm"
    "/Users/ilma4/.yarn"
    "/Users/ilma4/.bun"
    "/Users/ilma4/.swiftly"
    "/Users/ilma4/.gem"
    "/Users/ilma4/sdk"
    "/Users/ilma4/go"
    "/Users/ilma4/.sbt"
    "/Users/ilma4/golangci-lint"
    "/Users/ilma4/.skiko"
    "/Users/ilma4/.cargo"
    "/Users/ilma4/.rustup"
    "/Users/ilma4/.gradle"
    "/Users/ilma4/.m2"
    "/Users/ilma4/.nuget"
    "/Users/ilma4/.jupyter_kotlin"
    "/Users/ilma4/.bundle"
    "/Users/ilma4/Applications"
  ];
  backupReadAclScript = pkgs.writeShellScript "i4-backup-home-read-acl" ''
    set -euo pipefail

    /bin/chmod -R -a "backupuser allow list,search,readattr,readextattr,readsecurity,file_inherit,directory_inherit" /Users/ilma4 2>/dev/null || true
    /bin/chmod -R -a "backupuser allow read,readattr,readextattr,readsecurity" /Users/ilma4 2>/dev/null || true
    /bin/chmod -R -a "backup allow read,execute,list,search,readattr,readextattr,readsecurity,file_inherit,directory_inherit" /Users/ilma4 2>/dev/null || true
    if ! /bin/chmod -R +a "backup allow read,execute,list,search,readattr,readextattr,readsecurity,file_inherit,directory_inherit" /Users/ilma4; then
      echo "Warning: failed to update ACL on some protected or transient paths under /Users/ilma4." >&2
    fi
  '';
in {
  imports = [
    ../../modules/backup/backup.nix
  ];

  users.users.backup = {
    uid = 505;
    gid = 505;
    home = backupHome;
    createHome = true;
    isHidden = true;
  };

  users.groups.backup = {
    gid = 505;
    members = [config.users.users.backup.name];
  };

  users.knownUsers = [config.users.users.backup.name];
  users.knownGroups = [config.users.groups.backup.name];

  system.activationScripts.i4-backup-runtime-dirs.text = ''
    set -euo pipefail

    mkdir -p ${lib.escapeShellArg backupHome} ${lib.escapeShellArg "${backupHome}/.ssh"} ${lib.escapeShellArg backupCache} ${lib.escapeShellArg backupLocalRepo}
    chown ${lib.escapeShellArg "backup:backup"} ${lib.escapeShellArg backupHome} ${lib.escapeShellArg "${backupHome}/.ssh"} ${lib.escapeShellArg backupCache} ${lib.escapeShellArg backupLocalRepo}
    chmod 0750 ${lib.escapeShellArg backupHome} ${lib.escapeShellArg backupCache} ${lib.escapeShellArg backupLocalRepo}
    chmod 0700 ${lib.escapeShellArg "${backupHome}/.ssh"}
  '';

  system.activationScripts.i4-backup-user-home.text = ''
    set -euo pipefail

    ${backupReadAclScript}
  '';

  sops.secrets."quicksilver-backup-key" = {
    owner = "backup";
    group = "backup";
    mode = "0400";
  };
  sops.secrets.${localResticPasswordSecret} = {
    owner = "backup";
    group = "backup";
    mode = "0400";
  };
  sops.secrets.${remoteResticPasswordSecret} = {
    owner = "backup";
    group = "backup";
    mode = "0400";
  };

  i4.backup = {
    enable = true;
    backupUser = "backup";
    backupGroup = "backup";
    backupHour = 4;
    backupMinute = 0;
    paths = ["/Users/ilma4"];
    excludes = backupExcludePaths;
    localRepo = {
      location = backupLocalRepo;
      passwordFile = config.sops.secrets.${localResticPasswordSecret}.path;
    };
    remoteRepos.nas = {
      location = "rclone:quicksilver";
      passwordFile = config.sops.secrets.${remoteResticPasswordSecret}.path;
      extraResticArgs = [
        "-o"
        "rclone.program=${rcloneProgram}"
        "-o"
        "rclone.args=serve restic --stdio"
      ];
    };
  };

  launchd.daemons.i4-backup.serviceConfig = {
    EnvironmentVariables = {
      HOME = backupHome;
      RESTIC_CACHE_DIR = backupCache;
    };
    WorkingDirectory = backupHome;
  };

  launchd.daemons.i4-backup-home-read-acl = {
    serviceConfig = {
      ProgramArguments = ["${backupReadAclScript}"];
      RunAtLoad = true;
      StartCalendarInterval = [
        {
          Hour = 3;
          Minute = 55;
        }
      ];
      StandardOutPath = "/tmp/i4-backup-home-read-acl.log";
      StandardErrorPath = "/tmp/i4-backup-home-read-acl.log";
    };
  };
}
