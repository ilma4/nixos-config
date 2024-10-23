{ config, pkgs, ... }: 

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

    nonUs.remapTilde = true;
    remapCapsLockToEscape = true;

    #swapLeftCtrlAndFn = true;
  };

  security.pam.enableSudoTouchIdAuth = true;

  system.defaults.trackpad = {
    Clicking = true;
    TrackpadThreeFingerDrag = true;
    # Dragging = true;
  };

  # Auto upgrade nix package and the daemon service.
  services.nix-daemon.enable = true;
  nix.package = pkgs.nix;

  nixpkgs.config.allowUnfree = true; 
  # Necessary for using flakes on this system. 
  nix.settings.experimental-features = "nix-command flakes"; 

  homebrew = { 
    enable = true; 
    casks = [ 
      # Could be replaced by nix packages in future
      "firefox" 
      "thunderbird@esr" # esr is default for thunderbird
      "anki"
      "obs"
      "bitwarden"


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
      "whisky"

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


  services.karabiner-elements.enable = true; # remap keys: I remap lower tilde to Fn
  #services.skhd.enable = true; # hotkeys daemon
  services.skhd.skhdConfig = ''
# lalt - return : osascript ${config.home-manager.users.ilma4.home.file."itermNewWindow.scpt".source}

lalt - h : yabai -m window --focus west
lalt - l : yabai -m window --focus east
lalt - j : yabai -m window --focus south
lalt - k : yabai -m window --focus north

shift + lalt - h : yabai -m window --swap west
shift + lalt - l : yabai -m window --swap east
shift + lalt - j : yabai -m window --swap south
shift + lalt - k : yabai -m window --swap north

lalt - f : yabai -m window --toggle zoom-fullscreen
lalt - q : yabai -m window --close

lalt - e : yabai -m window --toggle split
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

