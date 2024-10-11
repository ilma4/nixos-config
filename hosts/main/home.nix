{ config, pkgs, modules, dotfiles, ... }:

{
  imports = [
    "${modules}/base.nix"
    "${modules}/personal.nix"
    ./gui-tweaks.nix
    ./sway.nix
    #"${modules}/gnome.nix"
    #./gui-cfg.nix
  ];

  home.username = "ilma4";
  home.homeDirectory = "/home/ilma4";


  targets.genericLinux.enable = true;

  services.playerctld.enable = true;

  services.easyeffects.enable = true;

  home.file = {
    ".config/easyeffects/irs/Sony MDR-7506 minimum phase 48000 Hz.irs".source = "${dotfiles}/easyeffects/Sony MDR-7506 minimum phase 48000 Hz.irs" ;
    ".config/easyeffects/output/Sony MDR-7506 no bass boost.json".source = "${dotfiles}/easyeffects/Sony MDR-7506 no bass boost.json";
  };

  
  #services.ssh-agent.enable = true;
  programs.ssh = {
    enable = true;
    addKeysToAgent = "yes";
    matchBlocks = {
      "ilma4-bkp" = { forwardAgent = true; };
      "nvc00731.amt.labs.intellij.net" = { forwardAgent = true; };
    };
  };

  programs.gpg.enable = true;
  services.gpg-agent = {
    enable = true;
    pinentryPackage = pkgs.pinentry-gnome3;
  };

  xdg.enable = true;
  xdg.mime.enable = true; # .desktop entryes for apps
  #xdg.portal.enable = true;
  #xdg.portal.extraPortals = [ pkgs.xdg-desktop-portal-wlr ];
  #xdg.portal.configPackages = [ pkgs.sway ];

  home.sessionPath = let HOME=config.home.homeDirectory; in [
    "${HOME}/.local/bin"
    "${HOME}/.local/share/JetBrains/Toolbox/scripts"
  ];

  home.packages = with pkgs; [
    cargo
    clang
    playerctl
    pkg-config
    bitwarden-cli
    #libreoffice-qt6-still
  ];

  # Use gcr4 as ssh-agent
  home.sessionVariables.SSH_AUTH_SOCK = "$XDG_RUNTIME_DIR/gcr/ssh";
  home.sessionVariables.ELECTRON_OZONE_PLATFORM_HINT="auto";
}
