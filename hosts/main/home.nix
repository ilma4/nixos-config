{ config, pkgs, ... }:

{
  imports = [
    ./../../common/home/base.nix
    ./../../common/home/personal.nix
  ];
  # Home Manager needs a bit of information about you and the paths it should
  # manage.
  home.username = "ilma4";
  home.homeDirectory = "/home/ilma4";

  targets.genericLinux.enable = true;
  xdg.mime.enable = true;

  nixpkgs.config.allowUnfree = true;
  
  #programs.zsh.initExtraBeforeCompInit = ''
  #  FPATH="$/usr/share/zsh/site-funztions:/usr/share/zsh/vendor-completions:$FPATH"
  #'';

  home.packages = with pkgs ; [
    # Drivers for non-nixos
    nixgl.nixGLIntel
    nixgl.nixVulkanIntel
  ];

  services.darkman.settings = {
    # Berlin 
    lat = 52.5;
    lng = 13.4;

    usegeoclue = true;
  };

  programs.firefox.enable = true;
  programs.chromium.enable = true;

  xdg.portal.extraPortals = [ pkgs.darkman ];
  xdg.portal.enable = true;
  xdg.portal.config = {
    preferred = {
      "org.freedesktop.impl.portal.Settings" = [ "darkman" ];
    };
  };

  # This value determines the Home Manager release that your configuration is
  # compatible with. This helps avoid breakage when a new Home Manager release
  # introduces backwards incompatible changes.
  #
  # You should not change this value, even if you update Home Manager. If you do
  # want to update the value, then make sure to first check the Home Manager
  # release notes.
  home.stateVersion = "24.05" ; # Please read the comment before changing.
}
