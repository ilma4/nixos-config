{
  config,
  lib,
  pkgs,
  inputs,
  ...
}: {
  imports = [
    ../../modules/nix-settings.nix
    ../../darwin-modules/launchd-agents.nix
    ../../modules/home-manager.nix
    ../../modules/sops.nix

    ../../modules/apps.nix

    inputs.home-manager-darwin.darwinModules.home-manager
    inputs.sops-nix-darwin.darwinModules.sops
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

  i4.launchd-agents.enable = true;
  i4.sops.enable = true;
  i4.apps.enable = true;

  nix.gc.automatic = false;

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

  environment.shells = [pkgs.zsh pkgs.fish];

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
    ../../certs/wildcard-ec.crt
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
      cleanup = "zap";
    };

    # TODO: enable with 25.11 release
    # greedyCasks = true; # always upgrade casks

    # common apps are configured in `modules/apps.nix`
    casks = [
      "codex-app"
    ];
    brews = [
      "steveyegge/beads/bd"
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
  system.activationScripts.trust-reverse-proxy-ca.text = ''
    set -euo pipefail
    security add-trusted-cert -d -r trustRoot \
      -k /Library/Keychains/System.keychain \
      ${../../certs/wildcard-ec.crt}
  '';
  */

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

  # Prometheus node exporter: monitoring
  services.prometheus.exporters.node.enable = true;
  users.users._prometheus-node-exporter.home = lib.mkForce "/private/var/lib/prometheus-node-exporter";

  programs.fish.enable = true;

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
