{
  config,
  inputs,
  lib,
  pkgs,
  ...
}: let
  cfg = config.i4.pi;
  nodejs = pkgs.nodejs_24;
  nixpkgs =
    if pkgs.stdenv.hostPlatform.isDarwin
    then inputs.nixpkgs-darwin
    else inputs.nixpkgs;
  # Nix skips profile upgrades when Pi's revision is unchanged, even if an
  # input override changed. A new nixpkgs revision needs a fresh profile.
  piProfile = "${config.home.homeDirectory}/.local/state/nix/profiles/pi-${nixpkgs.rev}";
  # Pi uses a separate nixpkgs input on Intel Darwin.
  nixpkgsInput =
    if pkgs.stdenv.hostPlatform.system == "x86_64-darwin"
    then "nixpkgs-darwin-x64"
    else "nixpkgs";
  piExtensions = [
    "npm:@juicesharp/rpiv-ask-user-question"
    "npm:@juicesharp/rpiv-web-tools"
    "git:github.com/alexei-ciobanu/pi-compaction-autocontinue"
    "npm:@howaboua/pi-codex-conversion"
  ];

  updateScript = pkgs.writeShellScriptBin "i4-update-pi" ''
    set -euo pipefail

    export HOME=${lib.escapeShellArg config.home.homeDirectory}
    export PATH="${piProfile}/bin:$HOME/.local/bin:${config.home.profileDirectory}/bin:''${PATH:-}:/usr/bin:/bin"

    mkdir -p ${lib.escapeShellArg (builtins.dirOf piProfile)}
    if [[ -e ${lib.escapeShellArg "${piProfile}/manifest.json"} ]]; then
      ${lib.getExe pkgs.nix} profile upgrade --profile ${lib.escapeShellArg piProfile} --all --refresh \
        --override-input ${nixpkgsInput} path:${nixpkgs.outPath}
    else
      ${lib.getExe pkgs.nix} profile add --profile ${lib.escapeShellArg piProfile} github:earendil-works/pi/stable \
        --override-input ${nixpkgsInput} path:${nixpkgs.outPath}
    fi
    ${lib.concatMapStringsSep "\n" (extension: "    pi install ${lib.escapeShellArg extension}") piExtensions}
    pi update --all
  '';
in {
  options.i4.pi.enable = lib.mkEnableOption "pi";

  config = lib.mkIf cfg.enable {
    i4.codex.enable = lib.mkDefault true; #

    # home.file.".pi/agent/models.json".source = ../hosts/quicksilver/pi/models.json;
    home.file.".pi/agent/extensions/notify-finish.ts".source = ../dotfiles/pi/extensions/notify-finish.ts;
    home.file.".pi/agent/extensions/compaction-count.ts".source = ../dotfiles/pi/extensions/compaction-count.ts;
    home.file.".pi/agent/extensions/codex-limit-autocontinue.ts".source = ../dotfiles/pi/extensions/codex-limit-autocontinue.ts;

    home.packages = [
      nodejs
      pkgs.bun
      updateScript
    ];
    home.sessionPath = lib.mkBefore ["${piProfile}/bin"];

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
