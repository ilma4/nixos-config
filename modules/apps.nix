{...}: let
  asLinuxPackage = x: {linuxInstallation = "package";} // x;
  macOnlyCask = x:
    {
      linuxInstallation = null;
      macInstallation = "cask";
    }
    // x;
  macOnlyBrew = x:
    {
      linuxInstallation = null;
      macInstallation = "brew";
    }
    // x;
  linuxOnlyProgram = x:
    {
      linuxInstallation = "program";
      macInstallation = null;
    }
    // x;
  # universal module
in {
  imports = [
    ./universall-apps.nix
  ];

  i4.apps.apps = {
    thunderbird = linuxOnlyProgram {}; # installed on mac using corporate thing
    obs-studio = {macName = "obs";};

    mpv = linuxOnlyProgram {}; # cli video player for linux. Use iina on mac
    iina = macOnlyCask {}; # good video play for mac with HDR support

    obsidian = asLinuxPackage {};
    todoist-electron = {macName = "todoist-app";};

    zed-editor = {macName = "zed";};

    # coding agents
    claude-code = asLinuxPackage {};
    codex = asLinuxPackage {};

    # lm-studio = asLinuxPackage {linuxName = "lmstudio";}; # run LLMs locally
    # comfyui = macOnlyCask {}; # tool for generating images/videos
    # cherry-studio = {}; # tool for LLMs

    firefox = {};
    vivaldi = asLinuxPackage {};
    browsers = asLinuxPackage {macName = "browsers-software/tap/browsers";}; # select browser when open link

    krita = asLinuxPackage {}; # image editor
    anki = asLinuxPackage {}; # learn word app
    calibre = asLinuxPackage {}; # book managment app

    telegram-desktop = {};

    discord = asLinuxPackage {};
    steam = {macInstallation = null;};
    heroic = asLinuxPackage {macInstallation = null;}; # GOG / Epic Games launcher
    prismlauncher = asLinuxPackage {macInstallation = null;}; # minecraft launcher
    dolphin-emu = asLinuxPackage {macInstallation = null;}; # Wii emulator

    qbittorrent = asLinuxPackage {};
    bitwarden-cli = asLinuxPackage {macInstallation = "package";};
    android-file-transfer = macOnlyCask {}; # app to transfer files between android and mac via usb
    utm = macOnlyCask {}; # qemu for mac
    macfuse = macOnlyCask {}; # FUSE for macOS, uses kernel extension

    displayplacer = macOnlyBrew {}; # cli to configure display resolution
    junie = macOnlyBrew {};
    shottr = macOnlyCask {};

    "1password-cli" = macOnlyCask {};
    # container = macOnlyBrew {}; # docker alternative from Apple. Runs each container in separate vm
    activitywatch = macOnlyCask {};
    cloudflare-warp = macOnlyCask {}; # corporate JetBrains VPN
    "zulu@21" = macOnlyCask {};
    "zulu@25" = macOnlyCask {};
    iterm2 = macOnlyCask {};
    itermai = macOnlyCask {};
    kitty = macOnlyCask {};
    # windows-app = macOnlyCask {}; # updated by corporate software
    # slack = macOnlyCask {}; # updated by corporate software
    karabiner-elements = macOnlyCask {}; # keyboard remapping
    raycast = macOnlyCask {}; # cmd+space : search apps and commands
    caffeine = macOnlyCask {};
    monitorcontrol = macOnlyCask {}; # control external monitor brightness
    "nikitabobko/tap/aerospace" = macOnlyCask {}; # tiling window manager
    marta = macOnlyCask {}; # file manager
    google-drive = macOnlyCask {};
    jordanbaird-ice = macOnlyCask {}; # edit menu bar
    vial = macOnlyCask {}; # configure my split keyboard
    skim = macOnlyCask {}; # pdf viewer
    eqmac = macOnlyCask {}; # equalizer for macos
    linearmouse = macOnlyCask {};
    deskpad = macOnlyCask {};
    easydict = macOnlyCask {};
    alt-tab = macOnlyCask {};
    blackhole-2ch = macOnlyCask {};
    # jetbrains-toolbox = macOnlyCask {};
    # "intellij-idea@eap" # as a platform developer, I use nightly builds from toolbox
    swiftly = macOnlyBrew {};
  };
}
