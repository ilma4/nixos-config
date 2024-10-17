{ config, pkgs, ... }: 

{
  # List packages installed in system profile. To search by name, run:
  # $ nix-env -qaP | grep wget
  environment.systemPackages = [ 
    pkgs.vim
  ];
    
  users.users.ilma4 = {
    home = "/Users/ilma4";
  };

  system.keyboard = {
    enableKeyMapping = true;

    remapCapsLockToEscape = true;
    nonUS.remapTilde = true;
    #swapLeftCtrlAndFn = true;
  };

  security.pam.enableSudoTouchIdAuth = true;

  system.defaults.trackpad = {
    Clicking = true;
    Dragging = true;
  };

  # Auto upgrade nix package and the daemon service.
  services.nix-daemon.enable = true;
  # nix.package = pkgs.nix;

  nixpkgs.config.allowUnfree = true; 
  # Necessary for using flakes on this system. 
  nix.settings.experimental-features = "nix-command flakes"; 

  homebrew = { 
    enable = true; 
    casks = [ 
      "firefox" 
      "thunderbird"
      "slack"

      "iterm2" 

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

  services.yabai = {
    enable = true;

  };

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

