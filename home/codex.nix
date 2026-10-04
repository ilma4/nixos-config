{
  config,
  inputs,
  lib,
  pkgs,
  ...
}: let
  cfg = config.i4.codex;
  nixpkgs =
    if pkgs.stdenv.hostPlatform.isDarwin
    then inputs.nixpkgs-darwin
    else inputs.nixpkgs;
  # A new nixpkgs revision needs a fresh profile even if Codex is unchanged.
  codexProfile = "${config.home.homeDirectory}/.local/state/nix/profiles/codex-${nixpkgs.rev}";

  loopScript = pkgs.writeShellScriptBin "codex-loop" ''
    set -euo pipefail

    if [[ $# -ne 2 || ! $1 =~ ^[1-9][0-9]*$ ]]; then
      printf 'Usage: %s ITERATIONS "PROMPT"\nITERATIONS must be a positive integer.\n' "$0" >&2
      exit 2
    fi

    iterations="$1"
    prompt="$2"

    for ((iteration = 1; iteration <= iterations; iteration++)); do
      printf '\nCodex session %s/%s\n' "$iteration" "$iterations" >&2
      printf '%s' "$prompt" | codex exec --yolo -
    done
  '';

  updateScript = pkgs.writeShellScriptBin "i4-update-codex" ''
    set -euo pipefail

    export HOME=${lib.escapeShellArg config.home.homeDirectory}
    export PATH="${codexProfile}/bin:$HOME/.local/bin:${config.home.profileDirectory}/bin:''${PATH:-}:/usr/bin:/bin"

    mkdir -p ${lib.escapeShellArg (builtins.dirOf codexProfile)} "$HOME/.local/bin"
    if [[ -e ${lib.escapeShellArg "${codexProfile}/manifest.json"} ]]; then
      ${lib.getExe pkgs.nix} profile upgrade --profile ${lib.escapeShellArg codexProfile} --all --refresh \
        --override-input nixpkgs path:${nixpkgs.outPath} --option accept-flake-config false
    else
      ${lib.getExe pkgs.nix} profile add --profile ${lib.escapeShellArg codexProfile} github:sadjow/codex-cli-nix#codex \
        --override-input nixpkgs path:${nixpkgs.outPath} --option accept-flake-config false
    fi
    # Upstream's wrapper uses this path for CODEX_EXECUTABLE_PATH.
    ln -sfn ${lib.escapeShellArg "${codexProfile}/bin/codex"} "$HOME/.local/bin/codex"
  '';
in {
  options.i4.codex.enable = lib.mkEnableOption "codex";

  config = lib.mkIf cfg.enable {
    home.shellAliases = {
      codex = "$HOME/.local/bin/codex --yolo";
    };

    home.packages = [
      updateScript
      loopScript
    ];
    home.sessionPath = lib.mkBefore ["${codexProfile}/bin"];

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
