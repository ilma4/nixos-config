{
  config,
  lib,
  pkgs,
  ...
}: {
  options.i4.launchd-agents.enable = lib.mkEnableOption "Enable launchd agents";

  config = lib.mkIf config.i4.launchd-agents.enable {
    /*
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
    */

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

    launchd.user.agents.keyboard-remap = {
      serviceConfig = {
        ProgramArguments = [
          "/bin/bash"
          "-c"
          ''
            set -euo pipefail

            device_match='{"VendorID":0x46d,"ProductID":0xb369}'
            key_mapping='{
              "UserKeyMapping": [
                {
                  "HIDKeyboardModifierMappingSrc": 0x700000064,
                  "HIDKeyboardModifierMappingDst": 0x700000035
                },
                {
                  "HIDKeyboardModifierMappingSrc": 0x700000035,
                  "HIDKeyboardModifierMappingDst": 0xFF00000003
                }
              ]
            }'
            max_wait_seconds=30
            deadline=$((SECONDS + max_wait_seconds))
            attempt=1

            # Logitech MX Keys Mini keyboard (VendorID 0x46d, ProductID 0xb369):
            #   Non-US \| (ISO key by left Shift) -> Grave/Tilde (`)
            #   Grave/Tilde (`)                   -> Fn / Globe
            while [ "$SECONDS" -lt "$deadline" ]; do
              if device_status=$(/usr/bin/hidutil property --matching "$device_match" --get UserKeyMapping) && /usr/bin/grep -q '^RegistryID' <<< "$device_status"; then
                echo "$(/bin/date): Logitech MX Keys Mini found; applying keyboard mapping"
                /usr/bin/hidutil property --matching "$device_match" --set "$key_mapping"
                echo "$(/bin/date): Keyboard mapping applied"
                exit 0
              fi

              echo "$(/bin/date): Logitech MX Keys Mini not found (attempt $attempt/$max_wait_seconds)"
              attempt=$((attempt + 1))
              /bin/sleep 1
            done

            echo "$(/bin/date): Logitech MX Keys Mini not found after $max_wait_seconds seconds; exiting"
            exit 1
          ''
        ];
        RunAtLoad = true;
        StandardOutPath = "/tmp/keyboard-remap.log";
        StandardErrorPath = "/tmp/keyboard-remap.log";
      };
    };
  };
}
