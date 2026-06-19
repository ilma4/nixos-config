{
  lib,
  osConfig,
  pkgs,
  ...
}: let
  homebrewPrefix = osConfig.homebrew.prefix or (lib.removeSuffix "/bin" osConfig.homebrew.brewPrefix);
in {
  imports = [
    ../../home/base.nix
    ./darwin-defaults-home.nix
    ./pi.nix
  ];

  config = {
    i4.fonts.enable = true;
    i4.zed.enable = true;
    i4.dev.enable = true;
    i4.neovim.enable = true;

    home.packages = with pkgs; [
      qemu

      (pkgs.writeShellScriptBin "bazel" ''
        set -euo pipefail
        exec ${pkgs.bazelisk}/bin/bazelisk "$@"
      '')

      nodejs_24
      monitor-input
      md4c # provides md2html, used by the "Paste from Markdown" Raycast script
      meslo-lgs-nf # Meslo Nerd Font patched for Powerlevel10k
    ];

    # Do not use home.sessionPath for Homebrew; it places Homebrew before Nix.
    home.sessionVariables = {
      PATH = "$PATH:${homebrewPrefix}/bin";
    };

    home.file = {
      ".config/aerospace/aerospace.toml".source = ../../dotfiles/aerospace.toml;
    };
  };
}
