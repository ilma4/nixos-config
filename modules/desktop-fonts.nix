{pkgs, ...}: {
  fonts = {
    packages = [pkgs.dejavu_fonts pkgs.jetbrains-mono];
    fontconfig = {
      enable = true;
      defaultFonts = {
        sansSerif = ["DejaVu Sans"];
        serif = ["DejaVu Serif"];
        monospace = ["JetBrains Mono"];
      };
    };
  };
}
