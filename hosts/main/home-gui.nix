{ config, pkgs, pkgs-unstable, ... }:

{
  imports = [
    ./sway.nix
    ./gui-apps.nix
  ];

  home.packages = (with pkgs ; [
    # Drivers for non-nixos
    nixgl.nixGLIntel
    nixgl.nixVulkanIntel
    #gnome.gnome-keyring
    #gnome.libgnome-keyring
    #gcr_4
    #gcr
    xdg-dbus-proxy
  ]) ++ (with pkgs-unstable; [ browsers ]); # TODO move to stable on nixpkgs 24.11

  home.pointerCursor = {
    name = "Adwaita";
    package = pkgs.gnome.adwaita-icon-theme;
    size = 48;
    x11 = {
      enable = true;
      defaultCursor = "Adwaita";
    };
  };


  services.gammastep = {
    enable = true;
    latitude = 52.5;
    longitude = 13.4;
  };

  #services.gnome-keyring = {
  #  enable = true;
  #  components = [ "pkcs11" "secrets" "ssh" ];
  #};
}

