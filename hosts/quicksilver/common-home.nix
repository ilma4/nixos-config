{pkgs, ...}: {
  imports = [
    ../../home/base.nix
    ./darwin-defaults-home.nix
  ];

  config = {
    i4.fonts.enable = true;
    i4.zed.enable = true;
    i4.dev.enable = true;
    i4.neovim.enable = true;

    home.packages = with pkgs; [
      qemu

      (pkgs.writeShellScriptBin "bazel" "${pkgs.bazelisk}/bin/bazelisk \"$@\"")

      nodejs_24
      beads-ui
      monitor-input
      meslo-lgs-nf # Meslo Nerd Font patched for Powerlevel10k
    ];

    programs.fish.enable = true;

    # home.sessionPath = ["/opt/homebrew/bin"]; # do not use, places before nix
    home.sessionVariables = {
      PATH = "$PATH:/opt/homebrew/bin";
    };

    home.file = {
      ".config/aerospace/aerospace.toml".source = ../../dotfiles/aerospace.toml;
    };
  };
}
