{
  config,
  lib,
  pkgs,
  ...
}: {
  options.i4.fonts = {
    enable = lib.mkEnableOption "fonts";
  };

  config = lib.mkIf config.i4.fonts.enable {
    home.packages = with pkgs; [
      # fonts
      powerline-fonts
      jetbrains-mono
    ];

    fonts.fontconfig.enable = true;
    fonts.fontconfig.defaultFonts.monospace = [
      "JetBrains Mono"
    ];
  };
}
