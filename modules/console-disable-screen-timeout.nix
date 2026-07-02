{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.i4.console-screen-timeout;
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
        StandardInput = "tty";
        StandardOutput = "tty";
        TTYPath = "/dev/tty1";
        RemainAfterExit = true;
      };

      # --powerdown (VESA power-off, not just blanking) can only be set via setterm
      # on a virtual console; the timer starts counting after the screen blanks
      script = ''
        set -euo pipefail
        ${pkgs.util-linux}/bin/setterm \
          --blank ${toString cfg.minutes} \
          --powerdown 1
      '';
    };
  };
}
