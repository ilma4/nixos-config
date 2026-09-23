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

    if [[ ! -e "$HOME/.local/share/junie/current" || ! -x ${npmPrefix}/bin/junie ]]; then
      curl -fsSL https://junie.jetbrains.com/install.sh | ${lib.getExe pkgs.bash}
    else
      junie update
    fi

    # The managed launcher applies an update on its next invocation.
    junie --version --skip-update-check
    if [[ -f "$HOME/.local/share/junie/updates/pending-update.json" ]]; then
      echo "Junie update is still pending; keeping installed versions" >&2
      exit 1
    fi

    junie_versions=$(cd -P "$HOME/.local/share/junie/versions" && pwd -P)
    current_junie=$(cd -P "$HOME/.local/share/junie/current" && pwd -P)
    if [[ "$(dirname "$current_junie")" != "$junie_versions" ]]; then
      echo "Junie current version is outside $junie_versions" >&2
      exit 1
    fi

    for version in "$junie_versions"/*; do
      [[ -d "$version" && ! -L "$version" ]] || continue
      [[ "$version" == "$current_junie" ]] || rm -rf -- "$version"
    done

    if [[ ! -d "$HOME/.local/share/claude/versions" || ! -x ${npmPrefix}/bin/claude ]]; then
      curl -fsSL https://claude.ai/install.sh | ${lib.getExe pkgs.bash}
    else
      claude update
    fi

    claude_versions=$(cd -P "$HOME/.local/share/claude/versions" && pwd -P)
    claude_target=$(readlink "${npmPrefix}/bin/claude")
    if [[ "$claude_target" != /* ]]; then
      claude_target="${npmPrefix}/bin/$claude_target"
    fi
    current_claude_dir=$(cd -P "$(dirname "$claude_target")" && pwd -P)
    if [[ "$current_claude_dir" != "$claude_versions" || ! -x "$claude_target" || -L "$claude_target" ]]; then
      echo "Claude launcher does not point to an installed version" >&2
      exit 1
    fi
    current_claude="$claude_versions/$(basename "$claude_target")"

    for version in "$claude_versions"/*; do
      [[ -f "$version" && ! -L "$version" ]] || continue
      [[ "$version" == "$current_claude" ]] || rm -f -- "$version"
    done
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
