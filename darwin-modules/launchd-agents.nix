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
        ProgramArguments = ["${lib.getExe pkgs.bash}" "-c" "set -euo pipefail; podman machine start"];
        RunAtLoad = true;
        AbandonProcessGroup = true; # required to keep podman machine process running
        StandardOutPath = "/tmp/podman-machine-start.log";
        StandardErrorPath = "/tmp/podman-machine-start.log.err";
      };
    };

    launchd.user.agents.obsidian-auto-commit = {
      path = [pkgs.coreutils pkgs.git];
      serviceConfig = {
        ProgramArguments = [
          "${lib.getExe pkgs.bash}"
          "-c"
          ''
            set -euo pipefail

            echo "$(date): Starting Obsidian auto-commit"

            if [ ! -d ~/Obsidian ]; then
              echo "$(date): ~/Obsidian directory not found, exiting"
              exit 0
            fi

            cd ~/Obsidian

            if [ ! -d .git ]; then
              echo "$(date): Not a git repository, exiting"
              exit 0
            fi

            # Calculate yesterday's date
            YESTERDAY=$(date -d 'yesterday' '+%Y-%m-%d' 2>/dev/null || date -v-1d '+%Y-%m-%d' 2>/dev/null || date -r $(($(date +%s) - 86400)) '+%Y-%m-%d')

            echo "$(date): Adding all changes to git"
            git add .

            # Check if there are any changes to commit
            if git diff --cached --quiet; then
              echo "$(date): No changes to commit"
              exit 0
            fi

            echo "$(date): Committing with message: $YESTERDAY"
            git commit -m "$YESTERDAY"

            echo "$(date): Auto-commit completed successfully"
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
  };
}
