{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.i4.coding-agents;
  nodejs = pkgs.nodejs_24;
  npm = lib.getExe' nodejs "npm";
  npmPrefix = "${config.home.homeDirectory}/.local";
  piPackage = "@earendil-works/pi-coding-agent";
  piPackageSpec = "${piPackage}@latest";

  updateScript = pkgs.writeShellScriptBin "i4-update-coding-agents" ''
    set -euo pipefail

    export HOME=${lib.escapeShellArg config.home.homeDirectory}
    export PATH="${npmPrefix}/bin:${config.home.profileDirectory}/bin:''${PATH:-}:/usr/bin:/bin"

    ${npm} install --global --prefix ${lib.escapeShellArg npmPrefix} --no-audit --no-fund ${piPackageSpec}
    pi update --all

    if [[ ! -e "$HOME/.codex/packages/standalone/current" || ! -x ${npmPrefix}/bin/codex ]]; then
      curl -fsSL https://chatgpt.com/codex/install.sh | CODEX_NON_INTERACTIVE=1 ${lib.getExe pkgs.bash}
    else
      codex update
    fi

    if [[ ! -e "$HOME/.local/share/junie/current" || ! -x ${npmPrefix}/bin/junie ]]; then
      curl -fsSL https://junie.jetbrains.com/install.sh | ${lib.getExe pkgs.bash}
    else
      junie update
    fi

    if [[ ! -d "$HOME/.local/share/claude/versions" || ! -x ${npmPrefix}/bin/claude ]]; then
      curl -fsSL https://claude.ai/install.sh | ${lib.getExe pkgs.bash}
    else
      claude update
    fi

    # Global installs have no lock file, so create one over the same
    # node_modules directory before running the requested audit fix.
    rm -f ${lib.escapeShellArg "${npmPrefix}/lib/package.json"} ${lib.escapeShellArg "${npmPrefix}/lib/package-lock.json"}
    ${npm} install --prefix ${lib.escapeShellArg "${npmPrefix}/lib"} --package-lock-only --ignore-scripts --no-audit --no-fund ${piPackageSpec}
    ${npm} --prefix ${lib.escapeShellArg "${npmPrefix}/lib"} audit fix apply
  '';
in {
  options.i4.coding-agents.enable = lib.mkEnableOption "coding agents";

  config = lib.mkIf cfg.enable {
    home.packages = [
      nodejs
      updateScript
    ];

    systemd.user.services.coding-agents-update.Service = {
      Type = "oneshot";
      ExecStart = lib.getExe updateScript;
    };

    systemd.user.timers.coding-agents-update = {
      Timer = {
        OnStartupSec = "1s";
        OnCalendar = "*-*-* 04:00:00";
        Persistent = true;
      };
      Install.WantedBy = ["timers.target"];
    };

    launchd.agents.coding-agents-update = {
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
