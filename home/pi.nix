{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.i4.pi;
  nodejs = pkgs.nodejs_24;
  npm = lib.getExe' nodejs "npm";
  npmPrefix = "${config.home.homeDirectory}/.local";
  piPackage = "@earendil-works/pi-coding-agent";
  piPackageSpec = "${piPackage}@latest";

  updateScript = pkgs.writeShellScriptBin "i4-update-pi" ''
    set -euo pipefail

    export HOME=${lib.escapeShellArg config.home.homeDirectory}
    export PATH="${npmPrefix}/bin:${config.home.profileDirectory}/bin:''${PATH:-}:/usr/bin:/bin"

    ${npm} install --global --prefix ${lib.escapeShellArg npmPrefix} --no-audit --no-fund ${piPackageSpec}
    pi update --all

    # Global installs have no lock file, so create one over the same
    # node_modules directory before running the requested audit fix.
    rm -f ${lib.escapeShellArg "${npmPrefix}/lib/package.json"} ${lib.escapeShellArg "${npmPrefix}/lib/package-lock.json"}
    ${npm} install --prefix ${lib.escapeShellArg "${npmPrefix}/lib"} --package-lock-only --ignore-scripts --no-audit --no-fund ${piPackageSpec}
    ${npm} --prefix ${lib.escapeShellArg "${npmPrefix}/lib"} audit fix apply
  '';
in {
  options.i4.pi.enable = lib.mkEnableOption "pi";

  config = lib.mkIf cfg.enable {
    i4.codex.enable = lib.mkDefault true; #

    # home.file.".pi/agent/models.json".source = ../hosts/quicksilver/pi/models.json;
    home.file.".pi/agent/extensions/notify-finish.ts".source = ../dotfiles/pi/extensions/notify-finish.ts;
    home.file.".pi/agent/extensions/compaction-count.ts".source = ../dotfiles/pi/extensions/compaction-count.ts;

    home.packages = [
      nodejs
      updateScript
    ];

    systemd.user.services.pi-update.Service = {
      Type = "oneshot";
      ExecStart = lib.getExe updateScript;
    };

    systemd.user.timers.pi-update = {
      Timer = {
        OnStartupSec = "1s";
        OnCalendar = "*-*-* 04:00:00";
        Persistent = true;
      };
      Install.WantedBy = ["timers.target"];
    };

    launchd.agents.pi-update = {
      enable = true;
      config = {
        ProgramArguments = [(lib.getExe updateScript)];
        RunAtLoad = true;
        StartCalendarInterval = [
          {
            Hour = 4;
            Minute = 0;
          }
        ];
      };
    };
  };
}
