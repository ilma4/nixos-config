{
  config,
  lib,
  pkgs,
  ...
}: {
  launchd.user.agents.podman-machine-autostart = {
    serviceConfig = {
      ProgramArguments = [
        "${pkgs.bash}/bin/bash"
        "-c"
        ''
          set -euo pipefail
          export PATH="$PATH:${pkgs.docker}/bin"
          echo $(whoami)

          echo "$(${pkgs.coreutils}/bin/date): Starting podman-machine"

          # Check if podman-machine is already running
          if ${pkgs.podman}/bin/podman machine ls >/dev/null 2>&1; then
            echo "$(${pkgs.coreutils}/bin/date): Podman-machine is already running"
            exit 0
          fi

          echo "$(${pkgs.coreutils}/bin/date): Starting podman-machine..."
          # ${pkgs.podman}/bin/podman machine start

          echo "$(${pkgs.coreutils}/bin/date): Podman-machine started successfully"
        ''
      ];
      RunAtLoad = true;
      StandardOutPath = "/tmp/colima-start.log";
      StandardErrorPath = "/tmp/colima-start.log";
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
    path = [pkgs.restic "/usr/bin"];
    serviceConfig = let
      resticprofile = "${pkgs.resticprofile}/bin/resticprofile -c ${lib.flake-location}/dotfiles/resticprofile.toml";
    in {
      ProgramArguments = [
        "/bin/bash" # do not changes, so wont lose permissions
        "-c"
        ''
          # set -euo pipefail # TODO workraound that if some files are unavailable to read, restic fails with exit code 3
          export SSH_AUTH_SOCK="$(launchctl getenv SSH_AUTH_SOCK)"

          echo "environment is:"
          env

          echo "$(${pkgs.coreutils}/bin/date): Starting resticprofile backups"

          ${resticprofile} backup
          ${resticprofile} hdd.copy

          echo "$(${pkgs.coreutils}/bin/date): resticprofile backups completed successfully"
        ''
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
}
