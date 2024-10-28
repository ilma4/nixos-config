{
  config,
  lib,
  pkgs,
  ...
}: {
  home.packages = with pkgs; [
    # fonts
    powerline-fonts
    jetbrains-mono
  ];

  fonts.fontconfig.enable = true;
  fonts.fontconfig.defaultFonts.monospace = [
    "JetBrains Mono"
  ];
}
