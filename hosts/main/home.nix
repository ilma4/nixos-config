{ config, lib, pkgs, modules, dotfiles, ... }:

{
  imports = [
    "${modules}/base.nix"
    "${modules}/personal.nix"
    ./gui-tweaks.nix
    ./sway.nix
    ./top-commands.nix
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

  top-commands.commands = lib.mkOptionDefault {
    suspend = "systemctl suspend";
    sleep = "systemctl suspend";
    reboot = "systemctl reboot";
  };

  programs.gpg.enable = true;
  services.gpg-agent = {
    enable = true;
    pinentryPackage = pkgs.pinentry-gnome3;
  };

  xdg.enable = true;
  xdg.mime.enable = true; # .desktop entryes for apps

  home.sessionPath = let HOME=config.home.homeDirectory; in [
    "${HOME}/.local/bin"
    "${HOME}/.local/share/JetBrains/Toolbox/scripts"
  ];

  home.packages = with pkgs; [
    playerctl
    pkg-config
    bitwarden-cli

    (pkgs.rust-bin.nightly.latest.default.override {
      extensions = [ "rust-src" ];
    })
  ];

  services.syncthing = {
    enable = true;
  };

  # Use gcr4 as ssh-agent
  home.sessionVariables.SSH_AUTH_SOCK = "$XDG_RUNTIME_DIR/gcr/ssh";

  home.sessionVariables.ELECTRON_OZONE_PLATFORM_HINT="auto";
}
