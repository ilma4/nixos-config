{ config, pkgs, ... }:

{
  home.packages = with pkgs ; [
    # Drivers for non-nixos
    nixgl.nixGLIntel
    nixgl.nixVulkanIntel
  ];

  home.pointerCursor = {
    name = "Adwaita";
    package = pkgs.gnome.adwaita-icon-theme;
    size = 48;
    x11 = {
      enable = true;
      defaultCursor = "Adwaita";
    };
  };


  programs.firefox.enable = true;
  programs.chromium.enable = true;

  programs.foot.enable = true;

  programs.waybar = {
    enable = true;
  };

  wayland.windowManager.sway.enable = true;
  wayland.windowManager.sway.config = rec {
    modifier = "Mod4";
    bars = [ { command = "\${pkgs.waybar}/bin/waybar"; } ];
  };
}
