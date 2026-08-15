{
  config,
  lib,
  pkgs,
  ...
}: let
  jetbrainsMaintenance = pkgs.writeShellScriptBin "i4-jetbrains-maintenance" ''
    set -euo pipefail

    export HOME=${lib.escapeShellArg config.home.homeDirectory}
    export PATH=${lib.escapeShellArg "${config.home.profileDirectory}/bin:/usr/bin:/bin:/usr/sbin:/sbin"}

    jetbrains_dir="$HOME/JetBrains"

    if [[ ! -d "$jetbrains_dir" ]]; then
      echo "Skipping JetBrains maintenance: $jetbrains_dir does not exist"
      exit 0
    fi

    printf '\n[%s] Cleaning JetBrains caches\n' "$(/bin/date '+%Y-%m-%d %H:%M:%S')"
    "$jetbrains_dir/clean-caches.sh"

    printf '\n[%s] Deduplicating %s\n' "$(/bin/date '+%Y-%m-%d %H:%M:%S')" "$jetbrains_dir"
    ${lib.getExe pkgs.jdupes} \
      --dedupe \
      --one-file-system \
      --permissions \
      --recurse \
      "$jetbrains_dir"

    git_status_failed=0
    for directory in "$jetbrains_dir"/*; do
      [[ -d "$directory" ]] || continue

      printf '\n[%s] git status: %s\n' "$(/bin/date '+%Y-%m-%d %H:%M:%S')" "$directory"
      if ! ${lib.getExe pkgs.git} -C "$directory" status; then
        git_status_failed=1
      fi
    done

    exit "$git_status_failed"
  '';
in {
  imports = [
    ./common-home.nix
    ../../modules/work.nix
  ];

  config = {
    home.username = "malakhov";
    i4.work.enable = true;
    i4.raycast = {
      enable = true;
      scripts = [
        "monitor-displayport.applescript"
        "kill-eqmac.applescript"
        "paste-from-markdown.sh"
      ];
    };
    programs.zsh.localVariables = {
      ZSH_DISABLE_COMPFIX = "true";
    };

    launchd.agents.central-proxy = {
      enable = true;
      config = {
        ProgramArguments = [
          "/Users/malakhov/.local/bin/central"
          "proxy"
          "start"
        ];
        RunAtLoad = true;
        AbandonProcessGroup = true;
        WorkingDirectory = "/Users/malakhov";
      };
    };

    launchd.agents.jetbrains-maintenance = {
      enable = true;
      config = {
        ProgramArguments = [(lib.getExe jetbrainsMaintenance)];
        StartCalendarInterval = [
          {
            Hour = 4;
            Minute = 0;
          }
        ];
        StandardOutPath = "/tmp/jetbrains-maintenance-malakhov.log";
        StandardErrorPath = "/tmp/jetbrains-maintenance-malakhov.err.log";
      };
    };

    rebuild-script = ''
      set -euo pipefail

      echo "Run darwin-rebuild for quicksilver from the ilma4 account." >&2
      exit 1
    '';

    home.packages = with pkgs; [
      blueutil # bluetooth CLI, used by the mic Raycast scripts
      terminal-notifier # auto-dismissing notifications for the mic Raycast scripts
      switchaudio-osx # SwitchAudioSource, used by the mic Raycast scripts

      jetbrainsMaintenance  # clean caches, dedupe files
    ];

    home.file = {
      ".config/karabiner".source = ../../dotfiles/karabiner;
      ".config/linearmouse/linearmouse.json".source = ../../dotfiles/linearmouse/linearmouse.json;
      ".config/zed".source = ../../dotfiles/zed;

      # malakhov-only Raycast mic scripts, deployed directly (not via the shared
      # i4.raycast registry) because they hard-code malakhov's home paths and must
      # not be installed into the ilma4 account. They connect the WH-1000XM5, stop
      # eqMac (via kill-eqmac.applescript), then switch the output/input devices.
      "Scripts/external-mic-malakhov.applescript" = {
        source = ../../home/raycast-scripts/external-mic-malakhov.applescript;
        executable = true;
      };
      "Scripts/builtin-mic-malakhov.applescript" = {
        source = ../../home/raycast-scripts/builtin-mic-malakhov.applescript;
        executable = true;
      };
    };
  };
}
