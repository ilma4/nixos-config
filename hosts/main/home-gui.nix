{ config, pkgs, ... }:

{
  imports = [
    ./sway.nix
    ./gui-apps.nix
  ];

  home.packages = with pkgs ; [
    # Drivers for non-nixos
    nixgl.nixGLIntel
    nixgl.nixVulkanIntel
    #xdg-dbus-proxy
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


  programs.foot.enable = true;

  programs.waybar = {
    enable = true;
  };

  services.gammastep = {
    enable = true;
    latitude = 52.5;
    longitude = 13.4;
  };

  wayland.windowManager.sway.enable = true;
  wayland.windowManager.sway.config = {
    modifier = "Mod4";
    bars = [ { command = "\${pkgs.waybar}/bin/waybar"; } ];
  };
}

