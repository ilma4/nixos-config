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

    # Auto-attach SSH logins to the shared tmux session, matching the Linux
    # hosts. This lives in quicksilver's common home module, so it applies to
    # both SSH-enabled users (ilma4 and malakhov).
    programs.zsh.initContent = lib.mkOrder 1100 ''
      if [[ -z "''${TMUX:-}" ]] && [[ -n "''${SSH_CONNECTION:-}" || -n "''${SSH_CLIENT:-}" || -n "''${SSH_TTY:-}" ]]; then
        tmux attach-session -t default || tmux new-session -s default
      fi
    '';

    # Do not use home.sessionPath for Homebrew; it places Homebrew before Nix.
    home.sessionVariables = {
      PATH = "$PATH:${homebrewPrefix}/bin";

      # brew is pinned and read-only under nix-homebrew, so skip its
      # auto-update before install/upgrade/tap. The var is presence-checked
      # (any non-empty value disables it), so use the documented "1" — not
      # "0", which reads as "enabled" and would mislead. Run `brew update`
      # manually when you want fresh formulae.
      HOMEBREW_NO_AUTO_UPDATE = "1";
    };

    home.file = {
      ".config/aerospace/aerospace.toml".source = ../../dotfiles/aerospace.toml;
    };
  };
}
