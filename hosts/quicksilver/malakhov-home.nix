{...}: {
  imports = [
    ./common-home.nix
    ../../modules/work.nix
  ];

  config = {
    home.username = "malakhov";
    i4.work.enable = true;
    i4.raycast = {
      enable = true;
      scripts = ["monitor-displayport.applescript"];
    };
    programs.zsh.localVariables = {
      ZSH_DISABLE_COMPFIX = "true";
    };

    rebuild-script = ''
      set -euo pipefail

      echo "Run darwin-rebuild for quicksilver from the ilma4 account." >&2
      exit 1
    '';

    home.file = {
      ".config/karabiner".source = ../../dotfiles/karabiner;
      ".config/linearmouse/linearmouse.json".source = ../../dotfiles/linearmouse/linearmouse.json;
      ".config/zed".source = ../../dotfiles/zed;
    };
  };
}
