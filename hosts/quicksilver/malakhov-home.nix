{pkgs, ...}: {
  imports = [
    ../../home/base.nix
    ./darwin-defaults-home.nix

    ../../modules/work.nix
  ];

  config = {
    home.username = "malakhov";
    i4.fonts.enable = true;
    i4.zed.enable = true;
    i4.work.enable = true;
    i4.dev.enable = true;
    i4.neovim.enable = true;

    rebuild-script = ''
      set -euo pipefail

      echo "Run darwin-rebuild for quicksilver from the ilma4 account." >&2
      exit 1
    '';

    home.packages = with pkgs; [
      qemu

      (pkgs.writeShellScriptBin "bazel" "${pkgs.bazelisk}/bin/bazelisk \"$@\"")

      nodejs_24
      beads-ui
      monitor-input
      meslo-lgs-nf
    ];

    programs.fish.enable = true;

    home.sessionVariables = {
      PATH = "$PATH:/opt/homebrew/bin";
    };

    home.file = {
      ".config/aerospace/aerospace.toml".source = ../../dotfiles/aerospace.toml;
      ".config/zed".source = ../../dotfiles/zed;
    };
  };
}
