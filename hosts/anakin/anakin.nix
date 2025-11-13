{
  config,
  lib,
  pkgs,
  inputs,
  ...
}: {
  imports = [
    inputs.home-manager.nixosModules.home-manager

    ../../home/base.nix
    ../../home/personal.nix
    ../../home/dev.nix
    ../../home/zed.nix

    ./gui-tweaks.nix
    ./sway.nix
    ./top-commands.nix
  ];

  nixpkgs.config.allowUnfree = true;

  home.username = "ilma4";

  i4.personal.enable = true;
  i4.zed.enable = true;
  i4.dev.enable = true;

  targets.genericLinux.enable = true;

  services.playerctld.enable = true;
  services.easyeffects.enable = true;

  home.file = {
    ".config/easyeffects/irs/Sony MDR-7506 minimum phase 48000 Hz.irs".source = ../../dotfiles/easyeffects/Sony MDR-7506 minimum phase 48000 Hz.irs;
    ".config/easyeffects/output/Sony MDR-7506 no bass boost.json".source = ../../dotfiles/easyeffects/Sony MDR-7506 no bass boost.json;
  };

  top-commands.commands = lib.mkOptionDefault {
    suspend = "systemctl suspend";
    sleep = "systemctl suspend";
    reboot = "systemctl reboot";
  };

  /*
  programs.gpg.enable = true;
  services.gpg-agent = {
    enable = true;
    pinentryPackage = pkgs.pinentry-gnome3;
  };
  */

  # xdg.enable = true;
  # xdg.mime.enable = true; # .desktop entryes for apps

  home.sessionPath = let
    HOME = config.home.homeDirectory;
  in [
    "${HOME}/.local/bin"
    "${HOME}/.local/share/JetBrains/Toolbox/scripts"
  ];

  home.packages = with pkgs; [
    playerctl
    pkg-config
    bitwarden-cli
  ];

  services.syncthing = {
    enable = true;
  };

  # Use gcr4 as ssh-agent
  home.sessionVariables.SSH_AUTH_SOCK = "$XDG_RUNTIME_DIR/gcr/ssh";

  home.sessionVariables.ELECTRON_OZONE_PLATFORM_HINT = "auto";
}
