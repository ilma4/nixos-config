{
  config,
  lib,
  pkgs,
  ...
}: {
  options.i4.launchd-agents.enable = lib.mkEnableOption "Enable launchd agents";

  config = lib.mkIf config.i4.launchd-agents.enable {
    launchd.user.agents.podman-machine-autostart = {
      path = [pkgs.podman];
      serviceConfig = {
        ProgramArguments = ["${pkgs.bash}/bin/bash" "-c" "podman machine start"];
        RunAtLoad = true;
        AbandonProcessGroup = true; # required to keep podman machine process running
        StandardOutPath = "/tmp/podman-machine-start.log";
        StandardErrorPath = "/tmp/podman-machine-start.log.err";
      };
    };

    launchd.user.agents.obsidian-auto-commit = {
      serviceConfig = {
        ProgramArguments = [
          "${pkgs.bash}/bin/bash"
          "-c"
          ''
            set -e

            echo "$(${pkgs.coreutils}/bin/date): Starting Obsidian auto-commit"

            if [ ! -d ~/Obsidian ]; then
              echo "$(${pkgs.coreutils}/bin/date): ~/Obsidian directory not found, exiting"
              exit 0
            fi

            cd ~/Obsidian

            if [ ! -d .git ]; then
              echo "$(${pkgs.coreutils}/bin/date): Not a git repository, exiting"
              exit 0
            fi

            # Calculate yesterday's date
            YESTERDAY=$(${pkgs.coreutils}/bin/date -d 'yesterday' '+%Y-%m-%d' 2>/dev/null || ${pkgs.coreutils}/bin/date -v-1d '+%Y-%m-%d' 2>/dev/null || ${pkgs.coreutils}/bin/date -r $(($(${pkgs.coreutils}/bin/date +%s) - 86400)) '+%Y-%m-%d')

            echo "$(${pkgs.coreutils}/bin/date): Adding all changes to git"
            ${pkgs.git}/bin/git add .

            # Check if there are any changes to commit
            if ${pkgs.git}/bin/git diff --cached --quiet; then
              echo "$(${pkgs.coreutils}/bin/date): No changes to commit"
              exit 0
            fi

            echo "$(${pkgs.coreutils}/bin/date): Committing with message: $YESTERDAY"
            ${pkgs.git}/bin/git commit -m "$YESTERDAY"

            echo "$(${pkgs.coreutils}/bin/date): Auto-commit completed successfully"
          ''
        ];
        StartCalendarInterval = [
          {
            Hour = 4;
            Minute = 0;
          }
        ];
        StandardOutPath = "/tmp/obsidian-auto-commit.log";
        StandardErrorPath = "/tmp/obsidian-auto-commit.log";
      };
    };

    launchd.user.agents.resticprofile-backup = {
      path = [pkgs.restic "/usr/bin" pkgs.resticprofile];
      serviceConfig = {
        ProgramArguments = [
          "${lib.getExe pkgs.resticprofile}"
          "-c"
          "${../dotfiles/resticprofile.toml}"
          "backup"
        ];
        StartCalendarInterval = [
          {
            Hour = 4;
            Minute = 0;
          }
        ];
        StandardOutPath = "/tmp/resticprofile-backups.log";
        StandardErrorPath = "/tmp/resticprofile-backups.log";
      };
    };

    launchd.user.agents.resticprofile-hddcopy = {
      path = [pkgs.restic "/usr/bin" pkgs.resticprofile];
      serviceConfig = {
        ProgramArguments = [
          "${lib.getExe pkgs.resticprofile}"
          "-c"
          "${../dotfiles/resticprofile.toml}"
          "hdd.copy"
        ];
        StartCalendarInterval = [
          {
            Hour = 4;
            Minute = 10;
          }
        ];
        StandardOutPath = "/tmp/resticprofile-hddcopy.log";
        StandardErrorPath = "/tmp/resticprofile-hddcopy.log";
      };
    };
  };
}
