{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.i4.console-screen-timeout;

  configureConsoleDisplayPowerSaving = pkgs.writeShellScript "configure-console-display-power-saving" ''
    set -euo pipefail

    if [[ ! -c /dev/tty1 ]]; then
      exit 0
    fi

    # A DRM modeset or resume can restore the panel while fbcon remains
    # logically blank. Unblank first so the inactivity timer is rearmed.
    ${pkgs.util-linux}/bin/setterm \
      --term linux \
      --blank poke \
      >/dev/tty1

    # --powersave uses an ioctl on stdin. Open tty1 directly rather than
    # asking systemd to acquire it as the service's controlling terminal.
    exec ${pkgs.util-linux}/bin/setterm \
      --term linux \
      --blank ${toString cfg.minutes} \
      --powersave powerdown \
      --powerdown 1 \
      </dev/tty1 \
      >/dev/tty1
  '';

  textConsoleActive = pkgs.writeCBin "text-console-active" ''
    #include <fcntl.h>
    #include <linux/kd.h>
    #include <sys/ioctl.h>
    #include <unistd.h>

    int main(void) {
      int mode = 0;
      int tty_fd = open("/dev/tty0", O_RDONLY | O_NOCTTY);

      if (tty_fd < 0) {
        return 2;
      }

      if (ioctl(tty_fd, KDGETMODE, &mode) < 0) {
        close(tty_fd);
        return 2;
      }

      close(tty_fd);
      return mode == KD_TEXT ? 0 : 1;
    }
  '';

  syncConsoleBacklightPower = pkgs.writeShellScript "sync-console-backlight-power" ''
    set -euo pipefail

    shopt -s nullglob
    declare -A blanked_by_us=()

    restore_backlights() {
      local power_file

      for power_file in "''${!blanked_by_us[@]}"; do
        if [[ -w "$power_file" ]]; then
          printf '0\n' >"$power_file" || true
        fi
        unset 'blanked_by_us[$power_file]'
      done
    }

    trap 'if ${textConsoleActive}/bin/text-console-active; then restore_backlights; fi' EXIT
    trap 'exit 0' INT TERM

    while true; do
      # In graphics mode the compositor owns the outputs. In particular,
      # i915 keeps bl_power at 4 when the compositor disables the panel.
      if ${textConsoleActive}/bin/text-console-active; then
        if [[ -r /sys/class/graphics/fb0/blank ]] \
          && IFS= read -r blank_state </sys/class/graphics/fb0/blank; then
          if [[ "$blank_state" == 4 ]]; then
            for power_file in /sys/class/backlight/*/bl_power; do
              [[ -w "$power_file" ]] || continue

              if IFS= read -r current_power <"$power_file" && [[ "$current_power" != 4 ]]; then
                printf '4\n' >"$power_file"
                blanked_by_us["$power_file"]=1
                printf 'Synchronizing %s to framebuffer power state 4\n' "$power_file" >&2
              fi
            done
          else
            restore_backlights
          fi
        fi
      elif [[ $? == 1 ]]; then
        # A graphics VT takes over via DRM/KMS, so forget our console state.
        # Keep it on a failed mode query, but don't write in that case either.
        blanked_by_us=()
      fi

      ${pkgs.coreutils}/bin/sleep 1
    done
  '';
in {
  options.i4.console-screen-timeout = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = !config.boot.isContainer;
      description = "Blank and power down the console display after a period of inactivity";
    };
    minutes = lib.mkOption {
      type = lib.types.ints.between 1 60;
      default = 1;
      description = "Minutes of inactivity before the console display blanks; it powers down one minute later";
    };
  };

  config = lib.mkIf cfg.enable {
    # Blanking is armed from early boot even if the service below never runs
    boot.kernelParams = ["consoleblank=${toString (cfg.minutes * 60)}"];

    systemd.services.console-display-power-saving = {
      description = "Configure console display power saving";
      wantedBy = ["multi-user.target"];
      after = ["systemd-vconsole-setup.service"];

      unitConfig.ConditionPathExists = "/dev/tty1";

      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        ExecStart = configureConsoleDisplayPowerSaving;
        # oneshot defaults to an infinite start timeout; never wedge activation
        TimeoutStartSec = "15s";
      };
    };

    # i915 can leave an eDP backlight on even after fbcon reaches
    # FB_BLANK_POWERDOWN. Mirror that final state to the backlight interface,
    # and restore only the backlights we changed when fbcon wakes. Leave
    # backlight control to Sway or another compositor in graphics mode.
    systemd.services.console-display-backlight-sync = {
      description = "Synchronize console powerdown with display backlights";
      wantedBy = ["multi-user.target"];
      after = ["console-display-power-saving.service"];

      unitConfig = {
        ConditionPathExists = "/sys/class/graphics/fb0/blank";
        ConditionDirectoryNotEmpty = "/sys/class/backlight";
      };

      serviceConfig = {
        Type = "simple";
        ExecStart = syncConsoleBacklightPower;
        Restart = "on-failure";
        RestartSec = "1s";
      };
    };

    # Resume restores the DRM connector while fbcon can remain logically blank.
    # ExecStop runs after wake-up and unblanks/rearms fbcon so its timer runs again.
    systemd.services.console-display-power-saving-sleep-hook = {
      description = "Rearm console display power saving after sleep";
      wantedBy = ["sleep.target"];
      before = ["sleep.target"];

      unitConfig = {
        DefaultDependencies = false;
        StopWhenUnneeded = true;
        ConditionPathExists = "/dev/tty1";
      };

      # Keep the unit active across sleep; the actual work runs in ExecStop after wake-up.
      script = ''
        set -euo pipefail
      '';

      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        ExecStop = configureConsoleDisplayPowerSaving;
        TimeoutStopSec = "15s";
      };
    };
  };
}
