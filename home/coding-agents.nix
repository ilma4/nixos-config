{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.i4.coding-agents;
  npmPrefix = "${config.home.homeDirectory}/.local";

  updateScript = pkgs.writeShellScriptBin "i4-update-coding-agents" ''
    set -euo pipefail

    export HOME=${lib.escapeShellArg config.home.homeDirectory}
    export PATH="${npmPrefix}/bin:${config.home.profileDirectory}/bin:''${PATH:-}:/usr/bin:/bin"

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
  '';
in {
  options.i4.coding-agents.enable = lib.mkEnableOption "coding agents";

  config = lib.mkIf cfg.enable {
    home.packages = [
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
