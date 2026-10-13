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
        "paste-from-markdown.sh"
        "builtin-mic.applescript"
        "wh-1000xm5-connect.applescript"
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
      ".config/linearmouse/linearmouse.json".source = ../../dotfiles/linearmouse/linearmouse.json;
      ".config/zed".source = ../../dotfiles/zed;

      # This user-specific external mic script also routes headphone output.
      "Scripts/external-mic-malakhov.applescript" = {
        source = ../../home/raycast-scripts/external-mic-malakhov.applescript;
        executable = true;
      };
    };
  };
}
