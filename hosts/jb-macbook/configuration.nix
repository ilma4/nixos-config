{
  config,
  lib,
  pkgs,
  inputs,
  modules,
  ...
}: {
  imports = [
    "${modules}/nix-settings.nix"
    # inputs.nix-rosetta-builder.darwinModules.default
  ];

  # environment.systemPackages = with pkgs; [
  # ];

  users.users = {
    ilma4 = {
      home = "/Users/ilma4";
    };
  };

  home-manager.users = {
    ilma4 = import ./ilma4-home.nix;
  };

  environment.shells = [pkgs.zsh];

  system.keyboard = {
    enableKeyMapping = true;
    remapCapsLockToEscape = true;
    # nonUS.remapTilde = true;
    #swapLeftCtrlAndFn = true;
  };

  security.pam.services.sudo_local.touchIdAuth = true;

  system.primaryUser = "ilma4";
  system.defaults.trackpad = {
    Clicking = true;
    TrackpadThreeFingerDrag = true;
    # Dragging = true; # enable when Apple fix input lag caused by it
  };

  system.defaults.NSGlobalDomain = {
    "com.apple.trackpad.scaling" = 2.0;
    "com.apple.keyboard.fnState" = true; # enable fn lock
  };

  system.defaults.spaces.spans-displays = false; # displays have separate spaces option (macos default is false)
  system.defaults.menuExtraClock.Show24Hour = true;
  system.defaults.finder = {
    ShowPathbar = true;
  };

  system.defaults.dock = {
    wvous-bl-corner = 1; # bottom left hot corner. disabled
    wvous-br-corner = 1; # bottom left hot corner. disabled
    wvous-tl-corner = 1; # top left hot corner. Mission Control
    # wvous-tl-corner = 2; # top left hot corner. Mission Control
    wvous-tr-corner = 1; # top left right corner. disabled

    mru-spaces = false; # disable rearrange spaces based on most recent use
    orientation = "bottom";

    autohide = true;
    autohide-time-modifier = 0.1;
  };

  system.defaults.WindowManager = {
    GloballyEnabled = false; # disable Stage Manager
  };

  homebrew = {
    enable = true;
    onActivation = {
      autoUpdate = true;
      upgrade = true;
      cleanup = "uninstall";
    };

    casks = [
      # Could be replaced by nix packages in future
      "firefox"
      "vivaldi"
      "thunderbird@esr" # esr is default for thunderbird
      "anki"
      "obs"
      # "bitwarden"
      "calibre"
      "1password-cli"
      "vlc"
      "iina" # player with HDR support
      "prismlauncher" # minecraft
      "heroic" # Epic Games/GOG launcher
      "activitywatch"
      "gitbutler"

      # Docker Desktop for Mac: vm to run docker containers
      # "docker" # i use colima instead

      #avaliable in nix, but nix has troubles with gui apps
      "telegram-desktop"
      "iterm2"
      "itermai"
      "obsidian"
      "slack"
      "visual-studio-code"
      "karabiner-elements" # keyboard remapping
      "discord"
      "browsers-software/tap/browsers"
      "utm" # qemu
      "raycast" # cmd+space : search apps and commands
      "caffeine"
      "monitorcontrol" # control external monitor brightness
      "far2l"
      "nikitabobko/tap/aerospace" # tiling window manager
      "jordanbaird-ice" # edit menu bar
      "zoom"
      "zed" # very fast text editor

      # Mac specific, most probably remain brew casks
      "macfuse" # FUSE for macOS, uses kernel extension

      "skim" # pdf viewer

      # fuse for macos, no kernel-extension, probably became better in the future
      # "macos-fuse-t/homebrew-cask/fuse-t"

      "whisky" # wine for macos
      "eqmac" # equalizer for macos

      "android-file-transfer" # transfer files from android (and Kindle) to mac via usb

      "linearmouse"
      # "middleclick" # can't open link in new tab in firefox with this
      "todoist"
      "deskpad"
      "easydict"
      "steam"

      "blackhole-2ch"

      # Jetbrains ides, may be replaced by nix packages but I'm not sure if i want to
      "jetbrains-toolbox"
      # "intellij-idea@eap" # as an IntelliJ developer, I use nightly builds from toolbox
    ];

    brews = [
      "displayplacer" # cli to configure displays
      "swiftly"

      "openjdk@21"
      "openjdk@17"
      "openjdk@11"
      # "openjdk@8"

      "bitwarden-cli"

      "resticprofile"
    ];

    masApps = {
      Xcode = 497799835;
      Bitwarden = 1352778147;
      WireGuard = 1451685025;
      V2BOX = 6446814690; # VLESS, Trojan, Shadowsocks VPN client
      AusweisApp = 948660805; # German ID card reader
    };
  };

  # TODO: use homebrew path from config
  system.activationScripts.aerospace-config.text = ''
    sudo --user=ilma4 -- /opt/homebrew/bin/aerospace reload-config
  '';

  /*
  environment.etc.hosts.text = lib.mkIf false ''
    ##
    # Host Database
    #
    # localhost is used to configure the loopback interface
    # when the system is booting.  Do not change this entry.
    ##
    127.0.0.1	localhost
    255.255.255.255	broadcasthost
    ::1             localhost

    ##
    0.0.0.0 habr.com
    ::1 habr.com

    0.0.0.0 www.phoronix.com
    ::1 www.phoronix.com
  '';
  */

  # uncomment on clean nix-darwin
  nix.linux-builder.enable = false;

  # nix-rosetta-builder.enable = false;
  # nix-rosetta-builder.onDemand = false;

  # VPN to access homelab
  services.tailscale.enable = true;

  # Create /etc/zshrc that loads the nix-darwin environment.
  programs.zsh.enable = true; # default shell on catalina

  # Set Git commit hash for darwin-version.
  system.configurationRevision = config.rev or config.dirtyRev or null;

  # Used for backwards compatibility, please read the changelog before changing.
  # $ darwin-rebuild changelog
  system.stateVersion = 5;

  # The platform the configuration will be used on.
  nixpkgs.hostPlatform = pkgs.system; # x86 or arm64, following pkgs
}
