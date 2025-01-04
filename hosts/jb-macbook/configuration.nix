{
  config,
  lib,
  pkgs,
  inputs,
  ...
}: {
  # List packages installed in system profile. To search by name, run:
  # $ nix-env -qaP | grep wget
  environment.systemPackages = with pkgs; [
    avahi
  ];

  users.users = {
    ilma4 = {
      home = "/Users/ilma4";
    };
    gggg = {
      home = "/Users/gggg";
      createHome = true;
    };
  };

  home-manager.users = {
    ilma4 = import ./ilma4-home.nix;
    gggg = import ./gggg-home.nix;
  };

  environment.shells = [pkgs.zsh];

  system.keyboard = {
    enableKeyMapping = true;

    # nonUS.remapTilde = true;
    remapCapsLockToEscape = true;

    #swapLeftCtrlAndFn = true;
  };

  security.pam.enableSudoTouchIdAuth = true;

  system.defaults.trackpad = {
    Clicking = true;
    TrackpadThreeFingerDrag = true;
    # Dragging = true; # enable when Apple fix input lag caused by it
  };

  system.defaults.NSGlobalDomain = {
    "com.apple.trackpad.scaling" = 2.0;

    "com.apple.keyboard.fnState" = true; # enable fn lock
  };

  system.defaults.spaces.spans-displays = true; # displays have separate spaces option (macos default is false)

  system.defaults.menuExtraClock.Show24Hour = true;

  system.defaults.finder = {
    ShowPathbar = true;
  };

  system.defaults.dock = {
    wvous-bl-corner = 1; # bottom left hot corner. disabled
    wvous-br-corner = 1; # bottom left hot corner. disabled
    wvous-tl-corner = 2; # top left hot corner. Mission Control
    wvous-tr-corner = 1; # top left right corner. disabled

    mru-spaces = false; # disable rearrange spaces based on most recent use
    orientation = "bottom";

    autohide = true;
    autohide-time-modifier = 0.1;
  };

  system.defaults.WindowManager = {
    GloballyEnabled = false; # disable Stage Manager
  };

  # Auto upgrade nix package and the daemon service.
  services.nix-daemon.enable = true;
  nix = {
    package = pkgs.nix;
    nixPath = ["nixpkgs=${inputs.nixpkgs}"]; # required for nixd
    gc.automatic = true;
    optimise.automatic = true;
    settings = {
      # allowed-users = [ "ilma4" ];
      # sandbox = false; # FIXME: broken on 24.11
      experimental-features = "nix-command flakes"; # Necessary for using flakes on this system.
    };
  };

  nixpkgs.config.allowUnfree = true;

  homebrew = {
    enable = true;
    onActivation = {
      cleanup = "uninstall";
    };

    casks = [
      # Could be replaced by nix packages in future
      "firefox"
      "thunderbird@esr" # esr is default for thunderbird
      "anki"
      "obs"
      "steam"
      # "bitwarden"
      "calibre"
      "1password-cli"
      "vlc"

      # I don't really understand docker on mac
      "docker"

      #avaliable in nix, but nix has troubles with gui apps
      "telegram-desktop"
      "iterm2"
      "obsidian"
      "slack"
      "visual-studio-code"
      "karabiner-elements"
      "discord"
      "zed"
      "browsers-software/tap/browsers"
      "prismlauncher"
      "utm"
      "raycast"
      "caffeine"
      "monitorcontrol"
      "alt-tab"
      "far2l"
      "nikitabobko/tap/aerospace"
      "zoom"

      # Mac specific, most probably remain brew casks
      "macfuse" # FUSE for macOS, uses kernel extension
      # "macos-fuse-t/homebrew-cask/fuse-t" # fuse for macos, no kernel-extension

      "linearmouse"
      # "middleclick" # can't open link in new tab in firefox with this
      "todoist"
      "deskpad"
      "easydict"

      "blackhole-2ch"
      "au-lab"
      "whisky" # wine for macos

      # Jetbrains ides, may be replaced by nix packages but I'm not sure if i want to
      "jetbrains-toolbox"
      "intellij-idea"
      "pycharm"
      "clion"
      "rustrover"
      "android-studio"
      "jetbrains-gateway"
    ];

    brews = [
      "openjdk@21"
      "openjdk@17"
      "openjdk@11"
      "openjdk@8"

      "bitwarden-cli"
      "screenresolution"
    ];

    masApps = {
      Xcode = 497799835;
      Bitwarden = 1352778147;
    };
  };

  environment.etc.hosts.text = ''
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

  #services.skhd.enable = true; # hotkeys daemon
  services.skhd.skhdConfig = ''
    # lalt - return : osascript ${config.home-manager.users.ilma4.home.file."itermNewWindow.scpt".source}
  '';

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
