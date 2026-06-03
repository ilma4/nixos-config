{
  config,
  lib,
  pkgs,
  inputs,
  ...
}: let
  homebrewPrefix = config.homebrew.prefix or (lib.removeSuffix "/bin" config.homebrew.brewPrefix);
in {
  imports = [
    ../../modules/nix-settings.nix
    ../../darwin-modules/launchd-agents.nix
    ../../modules/home-manager.nix
    ../../modules/sops.nix
    ./homebrew-auto-upgrade.nix
    ./backup.nix

    ../../modules/apps.nix

    inputs.home-manager-darwin.darwinModules.home-manager
    inputs.sops-nix-darwin.darwinModules.sops
  ];

  # environment.systemPackages = with pkgs; [
  # ];

  environment.systemPackages = [
    (pkgs.writeShellScriptBin "i4-revision" ''
      set -euo pipefail
      echo '${config.system.configurationRevision}'
    '')
  ];
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
    malakhov = {
      uid = 502;
      description = "Ilia Malakhov";
      home = "/Users/malakhov";
      shell = pkgs.zsh;
      createHome = true;
      isHidden = false;
    };
  };

  users.knownUsers = [
    config.users.users.malakhov.name
  ];

  home-manager.users = {
    ilma4 = import ./ilma4-home.nix;
    malakhov = import ./malakhov-home.nix;
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

  # Enable certificate management
  # security.pki.enable = true;

  # Add your .pem CA certificate
  security.pki.certificateFiles = [
    ../../certs/wildcard-ec.crt
    # You can add more certificates here
  ];

  fonts.packages = with pkgs; [
    meslo-lgs-nf
  ];

  homebrew = {
    enable = true;
    onActivation = {
      autoUpdate = false;
      upgrade = false;
      # TODO: enable when https://github.com/nix-darwin/nix-darwin/issues/1787 is resolved
      # cleanup = "zap";
    };

    # TODO: enable with 25.11 release
    # greedyCasks = true; # always upgrade casks

    # common apps are configured in `modules/apps.nix`
    casks = [
      "codex-app"
    ];
    brews = [
      "jetbrains/utils/teamcity"
      "steveyegge/beads/bd"
      "mas" # cli util to install apps from AppStore
    ];

    masApps = {
      Xcode = 497799835;
      Bitwarden = 1352778147;
      WireGuard = 1451685025;
      V2BOX = 6446814690; # VLESS, Trojan, Shadowsocks VPN client
      AusweisApp = 948660805; # German ID card reader
    };
  };

  system.activationScripts.aerospace-config.text = ''
    set -euo pipefail
    sudo --user=ilma4 -- ${homebrewPrefix}/bin/aerospace reload-config
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

  # VPN to access homelab
  services.tailscale.enable = true;

  # Create /etc/zshrc that loads the nix-darwin environment.
  programs.zsh.enable = true; # default shell on catalina
  programs.zsh.enableGlobalCompInit = false;

  # Set Git commit hash for darwin-version.
  system.configurationRevision = inputs.self.rev or inputs.self.dirtyRev or "null";

  # Used for backwards compatibility, please read the changelog before changing.
  # $ darwin-rebuild changelog
  system.stateVersion = 5;

  # The platform the configuration will be used on.
  nixpkgs.hostPlatform = pkgs.system; # x86 or arm64, following pkgs
}
