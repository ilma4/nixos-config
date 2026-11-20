{pkgs-unstable, ...}: let
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

    mpv = asLinuxPackage {macInstallation = null;}; # cli video player for linux. Use iina on mac
    iina = macOnlyCask {}; # good video play for mac with HDR support

    obsidian = asLinuxPackage {};
    todoist-electron = asLinuxPackage {macName = "todoist-app"; macInstallation = null;};

    zed-editor = asLinuxPackage {macName = "zed";};
    # kotlin-lsp = macOnlyBrew {macName = "jetbrains/utils/kotlin-lsp";};
    youtrack = macOnlyBrew {macName = "jetbrains/utils/youtrack";};
    vscode = {macName = "visual-studio-code";};

    # coding agents
    # antigravity-cli = asLinuxPackage {};

    # comfyui = macOnlyCask {}; # tool for generating images/videos
    # cherry-studio = {}; # tool for LLMs

    firefox = {};

    krita = asLinuxPackage {}; # image editor
    anki = asLinuxPackage {macInstallation = null;}; # learn word app
    calibre = asLinuxPackage {macInstallation = null;}; # book managment app

    telegram-desktop = asLinuxPackage {macInstallation = null;};

    discord = asLinuxPackage {macInstallation = null;};

    qbittorrent = asLinuxPackage {macInstallation = null;};
    bitwarden-cli = asLinuxPackage {macInstallation = null;};
    android-file-transfer = macOnlyCask {}; # app to transfer files between android and mac via usb
    utm = macOnlyCask {}; # qemu for mac
    macfuse = macOnlyCask {}; # FUSE for macOS, uses kernel extension

    displayplacer = macOnlyBrew {}; # cli to configure display resolution
    "incoai/tap/splash" = macOnlyBrew {}; # LLM inference engine, optimized for smaller models
    shottr = macOnlyCask {};

    "1password-cli" = macOnlyCask {};
    cloudflare-warp = macOnlyCask {}; # corporate JetBrains VPN
    "zulu@21" = macOnlyCask {};
    "zulu@25" = macOnlyCask {};
    # iterm2 = macOnlyCask {}; # managed by corporate software
    # handy = asLinuxPackage {package = pkgs-unstable.handy;}; # speech-to-text
    # windows-app = macOnlyCask {}; # updated by corporate software
    # slack = macOnlyCask {}; # updated by corporate software
    raycast = macOnlyCask {}; # cmd+space : search apps and commands
    caffeine = macOnlyCask {};
    monitorcontrol = macOnlyCask {}; # control external monitor brightness
    "nikitabobko/tap/aerospace" = macOnlyCask {}; # tiling window manager
    jordanbaird-ice = macOnlyCask {}; # edit menu bar
    skim = macOnlyCask {}; # pdf viewer
    linearmouse = macOnlyCask {};
    deskpad = macOnlyCask {};
    alt-tab = macOnlyCask {};
    blackhole-2ch = macOnlyCask {};
    # jetbrains-toolbox = macOnlyCask {};
    # "intellij-idea@eap" # as a platform developer, I use nightly builds from toolbox
    swiftly = macOnlyBrew {};
  };
}
