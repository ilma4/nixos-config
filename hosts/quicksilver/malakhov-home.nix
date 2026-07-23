{pkgs, ...}: {
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

    rebuild-script = ''
      set -euo pipefail

      echo "Run darwin-rebuild for quicksilver from the ilma4 account." >&2
      exit 1
    '';

    home.packages = with pkgs; [
      blueutil # bluetooth CLI, used by the mic Raycast scripts
      terminal-notifier # auto-dismissing notifications for the mic Raycast scripts
      switchaudio-osx # SwitchAudioSource, used by the mic Raycast scripts
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
