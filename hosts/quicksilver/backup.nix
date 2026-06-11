{
  config,
  lib,
  pkgs,
  constants,
  ...
}: let
  backupHome = "/Users/ilma4";
  backupCache = "${backupHome}/Library/Caches/restic";
  backupLocalRepo = "${backupHome}/NoBackup/restic";
  localResticPasswordSecret = "restic_password/quicksilver_local";
  remoteResticPasswordSecret = constants.nas.restic-ilma4.password-secret;
  hetzerResticPasswordSecret = constants.hetzer-restic.password-secret;
  backupSshKey = config.sops.secrets."quicksilver-backup-key".path;
  rcloneSshProgram = "${lib.getExe pkgs.openssh} -F /dev/null -i ${backupSshKey} -o BatchMode=yes -o IdentitiesOnly=yes -o StrictHostKeyChecking=accept-new -o UserKnownHostsFile=${backupHome}/.ssh/known_hosts";
  rcloneProgram = "${rcloneSshProgram} ilma4@nas.local";
  hetzerStorageBoxResticRepo = constants.hetzer-restic.repo;
  hetzerStorageBoxRcloneProgram = "${rcloneSshProgram} -p 23 u478838@u478838.your-storagebox.de rclone";
  backupExcludePaths = [
    "/Users/ilma4/Games"
    "/Users/ilma4/Library/Application Support/Steam"
    "/Users/ilma4/Library/Application Support/PrismLauncher"
    "/Users/ilma4/Downloads"
    "/Users/ilma4/NoBackup"
    "/Users/ilma4/.cache"
    "/Users/ilma4/.Trash"
    "/Users/ilma4/Library/Caches"
    "/Users/ilma4/Library/Android" # android sdks
    "/Users/ilma4/Library/Developer" # xcode stuff
    "/Users/ilma4/Library/Containers" # docker, vms, wine bottles
    "/Users/ilma4/Library/Java" # jdk's binaries
    "/Users/ilma4/Library/Logs"
    "/Users/ilma4/Library/Thunderbird/Profiles/*/ImapMail"
    "/Users/ilma4/Library/Application Support/JetBrains"
    "/Users/ilma4/Library/Application Support/com.apple.container" # docker from Apple
    "/Users/ilma4/Library/Application Support/JetBrains/*/plugins" # do not backup plugins for JetBrains IDEs
    "/Users/ilma4/Library/Application Support/Google" # do not backup google's apps
    "/Users/ilma4/Library/Application Support/Slack"
    "/Users/ilma4/Library/Application Support/Zed"

    # Electron caches(?)
    "/Users/ilma4/Library/Application Support/*/Cache"
    "/Users/ilma4/Library/Application Support/*/Code Cache"
    "/Users/ilma4/IdeaProjects" # test projects
    "/Users/ilma4/Library/Application Support/Code/CachedExtensionVSIXs"
    "/Users/ilma4/Library/Application Support/Vivaldi/*/File System" # do not backup Vivaldi's file system cache(?)
    "/Users/ilma4/Library/DuetExpertCenter" # https://apple.stackexchange.com/questions/476332/what-is-duetexpertcentre
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
    "/Users/ilma4/Virtual Machines.localized" # vmware-fusion VMs
    "/Users/ilma4/Projects/JetBrains" # too heavy and contains NDA code
    "/Users/ilma4/JetBrains" # too heavy and contains NDA code
    "/Users/ilma4/*/AeroSpace/.build"
    "/Users/ilma4/Projects/tdesktop"
    "/Users/ilma4/Projects/telegram"
    "/Users/ilma4/Projects/Telegram-Android"
    "/Users/ilma4/Projects/Nekogram"
    "/Users/ilma4/.android" # android emulator images
    "/Users/ilma4/.colima" # colima vm images, alternative to DockerDesktop for Mac
    "/Users/ilma4/.local/share"
    "/Users/ilma4/.vscode" # vscode extensions

    # caches
    "/Users/ilma4/.ollama" # LLMs
    "/Users/ilma4/.lmstudio" # LLMs
    "/Users/ilma4/.unsloth"
    "/Users/ilma4/.gemini" # oauth creds for gemini-cli
    "/Users/ilma4/.junie"
    "/Users/ilma4/.konan" # c++
    "/Users/ilma4/.lldb" # lldb
    "/Users/ilma4/.npm" # javascript!
    "/Users/ilma4/.yarn" # javascript!
    "/Users/ilma4/.bun" # javascript!
    "/Users/ilma4/.swiftly" # Swift!
    "/Users/ilma4/.gem" # ruby(?)
    "/Users/ilma4/sdk" # go
    "/Users/ilma4/go" # go
    "/Users/ilma4/.sbt" # scala
    "/Users/ilma4/golangci-lint" # go
    "/Users/ilma4/.skiko" # idk, just a guess, https://github.com/JetBrains/skiko
    "/Users/ilma4/.cargo" # rust
    "/Users/ilma4/.rustup" # rust
    "/Users/ilma4/.gradle"
    "/Users/ilma4/.m2" # maven
    "/Users/ilma4/.nuget" # .NET (?)
    "/Users/ilma4/.jupyter_kotlin"
    "/Users/ilma4/.bundle" # ruby(?)
    "/Users/ilma4/Applications"
  ];
in {
  imports = [
    ../../modules/backup/backup.nix
  ];

  sops.secrets."quicksilver-backup-key" = {
    owner = "ilma4";
    group = "staff";
    mode = "0400";
  };
  sops.secrets.${localResticPasswordSecret} = {
    owner = "ilma4";
    group = "staff";
    mode = "0400";
  };
  sops.secrets.${remoteResticPasswordSecret} = {
    owner = "ilma4";
    group = "staff";
    mode = "0400";
  };
  sops.secrets.${hetzerResticPasswordSecret} = {
    owner = "ilma4";
    group = "staff";
    mode = "0400";
  };

  i4.backup = {
    enable = true;
    backupUser = "ilma4";
    backupGroup = "staff";
    backupHour = 4;
    backupMinute = 0;
    paths = ["/Users/ilma4"];
    excludes = backupExcludePaths;
    localRepo = {
      location = backupLocalRepo;
      passwordFile = config.sops.secrets.${localResticPasswordSecret}.path;
    };
    remoteRepos = {
      nas = {
        location = "rclone:nas";
        passwordFile = config.sops.secrets.${remoteResticPasswordSecret}.path;
        extraResticArgs = [
          "-o"
          "rclone.program=${rcloneProgram}"
          "-o"
          "rclone.args=serve restic --stdio"
        ];
      };
      hetzer-storage-box = {
        location = "rclone:hetzer";
        passwordFile = config.sops.secrets.${hetzerResticPasswordSecret}.path;
        extraResticArgs = [
          "-o"
          "rclone.program=${hetzerStorageBoxRcloneProgram}"
          "-o"
          "rclone.args=serve restic --stdio --append-only ${hetzerStorageBoxResticRepo}"
        ];
      };
    };
  };

  launchd.user.agents.i4-backup.serviceConfig = {
    EnvironmentVariables = {
      HOME = backupHome;
      RESTIC_CACHE_DIR = backupCache;
    };
    WorkingDirectory = backupHome;
  };

  system.activationScripts.extraActivation.text = lib.mkAfter ''
    set -euo pipefail

    mkdir -p ${lib.escapeShellArg backupCache}
    chown ${lib.escapeShellArg "ilma4:staff"} ${lib.escapeShellArg backupCache}
    chmod 0750 ${lib.escapeShellArg backupCache}
  '';
}
