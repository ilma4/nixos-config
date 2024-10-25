{ config, lib, pkgs, ... }: 

{
  # List packages installed in system profile. To search by name, run:
  # $ nix-env -qaP | grep wget
  environment.systemPackages = with pkgs; [ 
    avahi
  ];
    
  users.users.ilma4 = {
    home = "/Users/ilma4";
  };

  system.keyboard = {
    enableKeyMapping = true;

    nonUS.remapTilde = true;
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

  system.defaults.spaces.spans-displays = true; # monitors have shared screens


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
  nix.package = pkgs.nix;

  nixpkgs.config.allowUnfree = true; 
  # Necessary for using flakes on this system. 
  nix.settings.experimental-features = "nix-command flakes"; 

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
      "bitwarden"
      "calibre"

      "docker"

      #avaliable in nix, but nix has troubles with gui apps
      "telegram-desktop"
      "iterm2"
      "obsidian"
      "slack"
      "visual-studio-code"
      "karabiner-elements"
      "discord"


     # Mac specific, most probably remain brew casks
      "macfuse" # FUSE for macOS

      "scroll-reverser"
      "linearmouse"
      # "middleclick" # can't open link in new tab in firefox with this
      "alt-tab"

      "raycast"
      # "alfred"


      "nikitabobko/tap/aerospace"

      "blackhole-2ch"
      "au-lab"
      "whisky" # wine for macos

     # Jetbrains ides, may be replaced by nix packages but I'm not sure if i want to
      "intellij-idea"
      "pycharm"
      "clion"
      "rustrover"
      "android-studio"
    ]; 

    brews = [
      "openjdk@21"
      "openjdk@17"
      "openjdk@11"
      "openjdk@8"


      "kdoctor" # jb tool for kotlin multiplatform
    ];
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


  #services.karabiner-elements.enable = true; # remap keys: I remap lower tilde to Fn
  #services.skhd.enable = true; # hotkeys daemon
  services.skhd.skhdConfig = ''
# lalt - return : osascript ${config.home-manager.users.ilma4.home.file."itermNewWindow.scpt".source}
'';


  # Create /etc/zshrc that loads the nix-darwin environment. 
  programs.zsh.enable = true;  # default shell on catalina 

  # Set Git commit hash for darwin-version.
  system.configurationRevision = config.rev or config.dirtyRev or null;

  # Used for backwards compatibility, please read the changelog before changing.
  # $ darwin-rebuild changelog
  system.stateVersion = 5;

  # The platform the configuration will be used on.
  nixpkgs.hostPlatform = "aarch64-darwin";
}

