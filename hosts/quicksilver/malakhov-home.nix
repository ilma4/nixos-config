{...}: {
  imports = [
    ./common-home.nix
    ../../modules/work.nix
  ];

  config = {
    home.username = "malakhov";
    i4.work.enable = true;

    rebuild-script = ''
      set -euo pipefail

      echo "Run darwin-rebuild for quicksilver from the ilma4 account." >&2
      exit 1
    '';

    home.file = {
      ".config/karabiner".source = ../../dotfiles/karabiner;
      ".config/zed".source = ../../dotfiles/zed;
    };
  };
}
