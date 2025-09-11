{
  config,
  lib,
  pkgs,
  inputs,
  ...
}: {
  imports = [
    "${lib.flake-location}/darwin-modules/nix-settings.nix"
    "${lib.flake-location}/darwin-modules/launchd-agents.nix"
    "${lib.flake-location}/modules/home-manager.nix"
    "${lib.flake-location}/modules/sops.nix"

    inputs.home-manager.darwinModules.home-manager
    inputs.nix-rosetta-builder.darwinModules.default
    inputs.sops-nix.darwinModules.sops
  ];

  # environment.systemPackages = with pkgs; [
  # ];

  /*
  environment.etc."hosts".text = ''
    ##
    # Host Database
    #
    # localhost is used to configure the loopback interface
    # when the system is booting.  Do not change this entry.
    ##
    127.0.0.1	localhost
    255.255.255.255	broadcasthost
    ::1             localhost
    0.0.0.0         habr.com
    0.0.0.0         www.phoronix.com
    0.0.0.0         news.ycombinator.com
  '';
  */

  networking.hostName = "DE-UNIT-1832";

  users.users = {
    ilma4 = {
      home = "/Users/ilma4";
      shell = pkgs.zsh;
    };
    backup = {
      uid = 505;
      gid = 505;
      # shell = pkgs.zsh;
    };
  };

  users.groups.backup = {
    gid = 505;
    members = [config.users.users.backup.name];
  };

  users.knownUsers = [config.users.users.backup.name];
  users.knownGroups = [config.users.groups.backup.name];

  home-manager.users = {
    ilma4 = import ./ilma4-home.nix;
  };

  environment.shells = [pkgs.zsh];

  /*
  remmapings are done in Karabiner-Elements
    system.keyboard = {
      enableKeyMapping = true;
      remapCapsLockToEscape = true;
      # nonUS.remapTilde = true;
      #swapLeftCtrlAndFn = true;
    };
  */

  security.pam.services.sudo_local.touchIdAuth = true;

  system.primaryUser = "ilma4";
  system.defaults.trackpad = {
    Clicking = true;
    TrackpadThreeFingerDrag = true;
    # Dragging = true; # enable when Apple fix input lag caused by it
  };

  # Enable certificate management
  # security.pki.enable = true;

  # Add your .pem CA certificate
  security.pki.certificateFiles = [
    "${lib.flake-location}/certs/ca.cert.pem"
    # You can add more certificates here
  ];

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

  fonts.packages = with pkgs; [
    meslo-lgs-nf
  ];

  homebrew = {
    enable = true;
    onActivation = {
      autoUpdate = true;
      upgrade = true;
      cleanup = "uninstall";
    };

    # TODO: enable with 25.11 release
    # greedyCasks = true; # always upgrade casks

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
      "dolphin" # Wii emulator
      "cloudflare-warp" # corporate JetBrains VPN

      # Docker Desktop for Mac: vm to run docker containers
      # "docker" # I use podman (including docker compatibility) instead
      # "podman-desktop" # I use "podman machine" directly

      "zulu@21"

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
      "vial" # configure my split keyboard
      "warp" # terminal with AI agent
      # "todoist"

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
      "deskpad"
      "easydict"
      "steam"
      "alt-tab"

      "blackhole-2ch"

      # Jetbrains ides, may be replaced by nix packages but I'm not sure if i want to
      "jetbrains-toolbox"
      # "intellij-idea@eap" # as an IntelliJ developer, I use nightly builds from toolbox
    ];

    brews = [
      "displayplacer" # cli to configure displays
      "swiftly"
      "gemini-cli"

      # FIXME: replace with nixpkgs version, when issue is resolved: https://github.com/NixOS/nixpkgs/issues/339576
      "bitwarden-cli"
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

  system.activationScripts.trust-reverse-proxy-ca.text = ''
        set -euo pipefail
        CERT="${lib.flake-location}/certs/ca.cert.pem"
        KEYCHAIN="/Library/Keychains/System.keychain"

        if [ ! -f "$CERT" ]; then
          echo "CA certificate not found: $CERT" >&2
          exit 0
        fi

        # Determine CN and new certificate SHA-1 fingerprint
        CN="$(${pkgs.openssl}/bin/openssl x509 -noout -subject -in "$CERT" | sed -n 's/.*CN[ =]*//p' | sed 's/,.*//')"
        NEW_SHA1="$(${pkgs.openssl}/bin/openssl x509 -noout -fingerprint -sha1 -in "$CERT" | cut -d'=' -f2 | tr -d ':\r' | tr '[:lower:]' '[:upper:]')"

        # Remove any existing certs with same CN but different fingerprint
        EXISTING_SHA1S="$(/usr/bin/security find-certificate -a -Z -c "$CN" "$KEYCHAIN" | awk '/SHA-1 hash:/ {print $3}' | tr -d '\r' | tr '[:lower:]' '[:upper:]')"
        if [ -n "$EXISTING_SHA1S" ]; then
          while read -r H; do
            [ -z "$H" ] && continue
            if [ "$H" != "$NEW_SHA1" ]; then
              /usr/bin/security delete-certificate -Z "$H" "$KEYCHAIN" || true
              echo "Removed old reverse-proxy CA from System keychain (SHA1=$H)"
            fi
          done <<EOF
    $EXISTING_SHA1S
    EOF
        fi

        # Install if exact cert is not already present
        if echo "$EXISTING_SHA1S" | grep -q "$NEW_SHA1"; then
          echo "Reverse-proxy CA already trusted in System keychain"
        else
          /usr/bin/security add-trusted-cert -d -r trustRoot -k "$KEYCHAIN" "$CERT"
          echo "Reverse-proxy CA installed into System keychain"
        fi
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
  # nix.linux-builder.enable = true;

  nix-rosetta-builder.enable = true;
  nix-rosetta-builder.onDemand = true; # builder sleeps when not in use

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
