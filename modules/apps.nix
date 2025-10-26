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
  linuxOnlyProgram = x:
    x
    // {
      linuxInstallation = "program";
      macInstallation = null;
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

    # cli video player for linux. Use iina on mac
    mpv = linuxOnlyProgram {};

    gemini-cli = asLinuxPackage {
      macInstallation = "brew";
    };

    bitwarden-cli = asLinuxPackage {
      macInstallation = "package";
    };

    iina = macOnlyCask {}; # good video play for mac with HDR support
    android-file-transfer = macOnlyCask {}; # app to transfer files between android and mac via usb
    utm = macOnlyCask {}; # qemu for mac

    macfuse = macOnlyCask {}; # FUSE for macOS, uses kernel extension
    # fuse for macos, no kernel-extension, probably became better in the future
    # "macos-fuse-t/homebrew-cask/fuse-t"

    displayplacer = macOnlyBrew {}; # cli to configure display resolution

    # Could be replaced by nix packages in future
    "1password-cli" = macOnlyCask {};
    activitywatch = macOnlyCask {};
    cloudflare-warp = macOnlyCask {}; # corporate JetBrains VPN
    "zulu@21" = macOnlyCask {};
    "zulu@25" = macOnlyCask {};
    #avaliable in nix, but nix has troubles with gui apps
    iterm2 = macOnlyCask {};
    itermai = macOnlyCask {};
    slack = macOnlyCask {};
    karabiner-elements = macOnlyCask {}; # keyboard remapping
    raycast = macOnlyCask {}; # cmd+space : search apps and commands
    caffeine = macOnlyCask {};
    monitorcontrol = macOnlyCask {}; # control external monitor brightness
    far2l = macOnlyCask {};
    "nikitabobko/tap/aerospace" = macOnlyCask {}; # tiling window manager
    jordanbaird-ice = macOnlyCask {}; # edit menu bar
    zoom = macOnlyCask {};
    vial = macOnlyCask {}; # configure my split keyboard
    # Mac specific, most probably remain brew casks
    skim = macOnlyCask {}; # pdf viewer
    eqmac = macOnlyCask {}; # equalizer for macos
    linearmouse = macOnlyCask {};
    deskpad = macOnlyCask {};
    easydict = macOnlyCask {};
    alt-tab = macOnlyCask {};
    blackhole-2ch = macOnlyCask {};
    # Jetbrains ides, may be replaced by nix packages but I'm not sure if i want to
    jetbrains-toolbox = macOnlyCask {};
    # "intellij-idea@eap" # as a platform developer, I use nightly builds from toolbox
    swiftly = macOnlyBrew {};
  };
}
