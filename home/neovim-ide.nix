{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.i4.neovim.ide;
  lazyVimPackages = with pkgs; [
    curl
    fd
    fzf
    git
    lazygit
    ripgrep
    stdenv.cc
    tree-sitter
  ];
in {
  options.i4.neovim.ide.enable = lib.mkEnableOption "the nvim-ide command with LazyVim";

  config = lib.mkIf (config ? home) {
    home.packages = lib.mkIf cfg.enable [
      (pkgs.writeShellScriptBin "nvim-ide" ''
        set -euo pipefail

        export NVIM_APPNAME="nvim-ide"
        if [ -n "''${PATH-}" ]; then
          export PATH="${lib.makeBinPath lazyVimPackages}:$PATH"
        else
          export PATH="${lib.makeBinPath lazyVimPackages}"
        fi

        exec ${lib.getExe pkgs.neovim} "$@"
      '')
    ];

    xdg.configFile."nvim-ide" = lib.mkIf cfg.enable {
      source = ../dotfiles/lazyvim;
      recursive = true;
    };
  };
}
