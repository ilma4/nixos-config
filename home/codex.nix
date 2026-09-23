{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.i4.codex;
  npmPrefix = "${config.home.homeDirectory}/.local";

  updateScript = pkgs.writeShellScriptBin "i4-update-codex" ''
    set -euo pipefail

    export HOME=${lib.escapeShellArg config.home.homeDirectory}
    export PATH="${npmPrefix}/bin:${config.home.profileDirectory}/bin:''${PATH:-}:/usr/bin:/bin"

    if [[ ! -e "$HOME/.codex/packages/standalone/current" || ! -x ${npmPrefix}/bin/codex ]]; then
      curl -fsSL https://chatgpt.com/codex/install.sh | CODEX_NON_INTERACTIVE=1 ${lib.getExe pkgs.bash}
    else
      codex update
    fi

    releases_dir=$(cd -P "$HOME/.codex/packages/standalone/releases" && pwd -P)
    current_release=$(cd -P "$HOME/.codex/packages/standalone/current" && pwd -P)
    if [[ "$(dirname "$current_release")" != "$releases_dir" ]]; then
      echo "Codex current release is outside $releases_dir" >&2
      exit 1
    fi

    for release in "$releases_dir"/*; do
      [[ -d "$release" && ! -L "$release" ]] || continue
      [[ "$release" == "$current_release" ]] || rm -rf -- "$release"
    done
  '';
in {
  options.i4.codex.enable = lib.mkEnableOption "codex";

  config = lib.mkIf cfg.enable {
    home.shellAliases = {
      codex = "$HOME/.local/bin/codex --yolo";
    };

    home.packages = [
      updateScript
    ];

    systemd.user.services.codex-update.Service = {
      Type = "oneshot";
      ExecStart = lib.getExe updateScript;
    };

    systemd.user.timers.codex-update = {
      Timer = {
        OnStartupSec = "1s";
        OnCalendar = "*-*-* 04:00:00";
        Persistent = true;
      };
      Install.WantedBy = ["timers.target"];
    };

    launchd.agents.codex-update = {
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
