{
  config,
  lib,
  pkgs,
  ...
}: let
  asLinuxPackage = x: x // {linuxInstallation = "package";};
  macOnlyCask = x:
    x
    // {
      linuxInstallation = null;
      macInstallation = "cask";
    };
  macOnlyBrew = x:
    x
    // {
      linuxInstallation = null;
      macInstallation = "brew";
    };
in {
  imports = [
    ./universall-apps.nix
  ];

  i4-apps.apps = {
    firefox = {};
    thunderbird = {
      macName = "thunderbird@esr";
    };

    obs-studio = {
      macName = "obs";
    };
    vlc = {};

    obsidian = asLinuxPackage {};

    zed-editor = {
      macName = "zed";
    };

    vivaldi = asLinuxPackage {};

    # git client with virtual branches
    gitbutler = asLinuxPackage {};

    visual-studio-code = {};

    # terminal with AI agent
    warp-terminal = {
      macName = "warp";
    };

    todoist-electron = {
      macName = "todoist";
    };

    # image editor
    krita = asLinuxPackage {};

    # run llms locally
    lm-studio = asLinuxPackage {};

    # learn word app
    anki = asLinuxPackage {};

    # book managment app
    calibre = asLinuxPackage {};

    # select browser when open link
    browsers = asLinuxPackage {
      macName = "browsers-software/tap/browsers";
    };

    discord = asLinuxPackage {};

    steam = {};

    # GOG / Epic Games launcher
    heroic = asLinuxPackage {};

    # minecraft launcher
    prismlauncher = asLinuxPackage {};

    # Wii emulator
    dolphin-emu = asLinuxPackage {
      macName = "dolphin";
    };

    qbittorrent = asLinuxPackage {};

    # cli video player for linux
    mpv = {
      macInstallation = null; # use iina instead
    };

    gemini-cli = asLinuxPackage {
      macInstallation = "brew";
    };

    iina = macOnlyCask {}; # good video play for mac with HDR support
    android-file-transfer = macOnlyCask {}; # app to transfer files between android and mac via usb
    utm = macOnlyCask {}; # qemu for mac
    macfuse = macOnlyCask {}; # FUSE for macOS, uses kernel extension
    displayplacer = macOnlyBrew {}; # cli to configure display resolution
  };
}
