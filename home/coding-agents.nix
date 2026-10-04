{
  config,
  inputs,
  lib,
  pkgs,
  ...
}: let
  cfg = config.i4.coding-agents;
  npmPrefix = "${config.home.homeDirectory}/.local";
  nixpkgs =
    if pkgs.stdenv.hostPlatform.isDarwin
    then inputs.nixpkgs-darwin
    else inputs.nixpkgs;
  # A new nixpkgs revision needs a fresh profile even if Claude is unchanged.
  claudeProfile = "${config.home.homeDirectory}/.local/state/nix/profiles/claude-${nixpkgs.rev}";

  updateScript = pkgs.writeShellScriptBin "i4-update-coding-agents" ''
    set -euo pipefail

    export HOME=${lib.escapeShellArg config.home.homeDirectory}
    export PATH="${claudeProfile}/bin:${npmPrefix}/bin:${config.home.profileDirectory}/bin:''${PATH:-}:/usr/bin:/bin"

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

    mkdir -p ${lib.escapeShellArg (builtins.dirOf claudeProfile)} "$HOME/.local/bin"
    if [[ -e ${lib.escapeShellArg "${claudeProfile}/manifest.json"} ]]; then
      ${lib.getExe pkgs.nix} profile upgrade --profile ${lib.escapeShellArg claudeProfile} --all --refresh \
        --override-input nixpkgs path:${nixpkgs.outPath} --option accept-flake-config false
    else
      ${lib.getExe pkgs.nix} profile add --profile ${lib.escapeShellArg claudeProfile} github:ryoppippi/nix-claude-code#stable \
        --override-input nixpkgs path:${nixpkgs.outPath} --option accept-flake-config false
    fi
    # Preserve existing aliases and callers of the standalone launcher.
    ln -sfn ${lib.escapeShellArg "${claudeProfile}/bin/claude"} "$HOME/.local/bin/claude"
  '';
in {
  options.i4.coding-agents.enable = lib.mkEnableOption "coding agents";

  config = lib.mkIf cfg.enable {
    home.packages = [
      updateScript
    ];
    home.sessionPath = lib.mkBefore ["${claudeProfile}/bin"];

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
