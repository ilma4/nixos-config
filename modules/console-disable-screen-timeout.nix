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
