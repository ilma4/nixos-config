{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.i4.pi;
  nodejs = pkgs.nodejs_24;
  agentDir = "${config.home.homeDirectory}/.pi/agent";
  piExtensions = [
    "npm:@juicesharp/rpiv-ask-user-question"
    "npm:@juicesharp/rpiv-web-tools"
    "git:github.com/alexei-ciobanu/pi-compaction-autocontinue"
    "npm:@howaboua/pi-codex-conversion"
  ];

  haPiScript = pkgs.writeShellScriptBin "ha-pi" (lib.replaceStrings
    ["@ssh@" "@node@" "@extension@"]
    [
      (
        if pkgs.stdenv.hostPlatform.isDarwin
        then "/usr/bin/ssh"
        else lib.getExe pkgs.openssh
      )
      (lib.getExe' nodejs "node")
      (lib.escapeShellArg "${../dotfiles/pi/extensions/ha-mcp.ts}")
    ]
    (builtins.readFile ../scripts/ha-pi.sh));

  updateScript = pkgs.writeShellScriptBin "i4-update-pi" ''
    set -euo pipefail

    export HOME=${lib.escapeShellArg config.home.homeDirectory}
    export PATH="${agentDir}/bin:${config.home.homeDirectory}/.local/bin:${lib.makeBinPath [nodejs pkgs.curl]}:${config.home.profileDirectory}/bin:''${PATH:-}:/usr/bin:/bin"

    # Bootstrap once. The official installer also migrates the old global npm
    # installation, removing it only after the managed installation succeeds.
    if [[ ! -f ${lib.escapeShellArg "${agentDir}/install/managed-install.json"} ]]; then
      installer=$(mktemp)
      trap 'rm -f "$installer"' EXIT
      curl -fsSL https://pi.dev/install.sh -o "$installer"
      sh "$installer"
    fi

    # Use the managed launcher explicitly, even if an old pi shadows it.
    pi() { ${lib.escapeShellArg "${agentDir}/bin/pi"} "$@"; }
    ${lib.concatMapStringsSep "\n" (extension: "    pi install ${lib.escapeShellArg extension}") piExtensions}
    pi update --all
  '';
in {
  options.i4.pi.enable = lib.mkEnableOption "pi";

  config = lib.mkIf cfg.enable {
    i4.codex.enable = lib.mkDefault true; #

    home.file.".pi/agent/extensions/notify-finish.ts".source = ../dotfiles/pi/extensions/notify-finish.ts;
    home.file.".pi/agent/extensions/compaction-count.ts".source = ../dotfiles/pi/extensions/compaction-count.ts;
    home.file.".pi/agent/extensions/codex-limit-autocontinue.ts".source = ../dotfiles/pi/extensions/codex-limit-autocontinue.ts;

    home.packages = [
      nodejs
      pkgs.bun
      updateScript
      haPiScript
    ];

    home.sessionPath = ["${agentDir}/bin"];

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
