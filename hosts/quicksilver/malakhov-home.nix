{
  config,
  pkgs,
  ...
}: {
  imports = [
    ./common-home.nix
    ./splash.nix
    ../../modules/work.nix
  ];

  config = {
    home.username = "malakhov";
    i4.work.enable = true;
    i4.raycast = {
      enable = true;
      scripts = [
        "chrome.applescript"
        "monitor-displayport.applescript"
        "paste-from-markdown.sh"
        "builtin-mic.applescript"
        "wh-1000xm5-connect.applescript"
      ];
    };
    programs.zsh.localVariables = {
      ZSH_DISABLE_COMPFIX = "true";
    };

    programs.git.includes = [
      {
        condition = "gitdir:${config.flake-source}/.git";
        contents.user.email = "ilya.malakhov4@gmail.com";
      }
    ];

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

    flake-source = "${config.home.homeDirectory}/.config/nixos-config";
    rebuild-flake-output = "quicksilver";

    home.packages = with pkgs; [
      blueutil # bluetooth CLI, used by the mic Raycast scripts
      terminal-notifier # auto-dismissing notifications for the mic Raycast scripts
      switchaudio-osx # SwitchAudioSource, used by the mic Raycast scripts
    ];

    home.file = {
      ".config/linearmouse/linearmouse.json".source = ../../dotfiles/linearmouse/linearmouse.json;
      # ~/.config/zed is deployed by ../../home/zed.nix (it merges Nix-tooling
      # settings only on hosts that install those tools).

      # This user-specific external mic script also routes headphone output.
      "Scripts/external-mic-malakhov.applescript" = {
        source = ../../home/raycast-scripts/external-mic-malakhov.applescript;
        executable = true;
      };
    };
  };
}
