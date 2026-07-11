{
  config,
  lib,
  pkgs,
  inputs,
  constants,
  ...
}: let
  homebrewPrefix = config.homebrew.prefix or (lib.removeSuffix "/bin" config.homebrew.brewPrefix);
  reverseProxyCert = ../../certs/wildcard-ec.crt;
  haveReverseProxyCert = builtins.pathExists reverseProxyCert;
in {
  imports = [
    ../../modules/nix-settings.nix
    ../../darwin-modules/launchd-agents.nix
    ../../darwin-modules/keyboard-watcher.nix
    ../../modules/home-manager.nix
    ../../modules/sops.nix
    ./homebrew-auto-upgrade.nix
    ./backup.nix
    ./mlx.nix
    #./llama.nix
    ./restic-full-disk-access-wrapper.nix

    ../../modules/apps.nix

    inputs.home-manager-darwin.darwinModules.home-manager
    inputs.sops-nix-darwin.darwinModules.sops
    inputs.nix-homebrew.darwinModules.nix-homebrew
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
  i4.keyboard-watcher.enable = true;
  i4.sops.enable = true;
  i4.apps.enable = true;

  # HA long-lived token for the ha-mcp server (home/ha-mcp.nix), readable by the agent user.
  sops.secrets."homeassistant/token" = {
    owner = "ilma4";
    mode = "0400";
  };

  nix.gc.automatic = false;

  networking.hostName = "DE-UNIT-1832";

  users.users = {
    ilma4 = {
      home = "/Users/ilma4";
      shell = pkgs.zsh;
      openssh.authorizedKeys.keys = [constants.ios-pub-key];
    };
    malakhov = {
      uid = 502;
      description = "Ilia Malakhov";
      home = "/Users/malakhov";
      shell = pkgs.zsh;
      createHome = true;
      isHidden = false;
      openssh.authorizedKeys.keys = [constants.ios-pub-key];
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

  # Let the work user (malakhov) stop the eqMac app that runs in ilma4's login
  # session; killing another user's process needs root. ilma4 owns the app and
  # stops it without sudo. Scoped to exactly this command. Used by
  # ~/Scripts/kill-eqmac.applescript.
  security.sudo.extraConfig = ''
    malakhov ALL=(ALL) NOPASSWD: /usr/bin/pkill -x eqMac
  '';

  system.primaryUser = "ilma4";

  # Enable certificate management
  # security.pki.enable = true;

  # Add your .pem CA certificate
  security.pki.certificateFiles = lib.optional haveReverseProxyCert reverseProxyCert;

  fonts.packages = with pkgs; [
    meslo-lgs-nf
  ];

  # nix-homebrew installs and owns the Homebrew prefix itself (the `brew`
  # binary and its source), pinned via the `brew-src` flake input. The
  # `homebrew` block below still declares which formulae/casks/masApps to
  # install on top of it.
  nix-homebrew = {
    enable = true;
    user = "ilma4"; # owner of the existing /opt/homebrew prefix (group: admin)

    # Keep imperative tap management. The private `jetbrains/junie` and
    # `jetbrains/utils` taps (plus `nikitabobko/tap`) can't be public flake
    # inputs, so fully-declarative taps (mutableTaps = false) isn't viable.
    # Defaults to true; kept explicit to document the decision.
    mutableTaps = true;

    # Homebrew's PATH is added deliberately *after* Nix in
    # hosts/quicksilver/common-home.nix. Don't let nix-homebrew prepend it via
    # a slow `eval "$(brew shellenv)"` on every interactive shell.
    enableZshIntegration = false;
    enableBashIntegration = false;
    enableFishIntegration = false;
  };

  homebrew = {
    enable = true;
    onActivation = {
      extraFlags = [
        "--force-cleanup" # TODO: remove when https://github.com/nix-darwin/nix-darwin/issues/1787 is resolved
      ];
      autoUpdate = false;
      upgrade = false;
      cleanup = "zap";
    };

    # TODO: enable with 25.11 release
    # greedyCasks = true; # always upgrade casks

    # common apps are configured in `modules/apps.nix`
    casks = [
    ];
    brews = [
      "jetbrains/utils/teamcity"
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

  system.activationScripts.extraActivation.text = lib.mkAfter (
    ''
      set -euo pipefail
      /usr/bin/sudo --user=ilma4 -- ${homebrewPrefix}/bin/aerospace reload-config
    ''
    + lib.optionalString haveReverseProxyCert ''
      if ! /usr/bin/security verify-cert -c ${reverseProxyCert} >/dev/null 2>&1; then
        /usr/bin/security add-trusted-cert -d -r trustRoot \
          -k /Library/Keychains/System.keychain \
          ${reverseProxyCert}
      fi
    ''
  );

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

  # SSH access from the iOS key only, for personal and work users.
  services.openssh = {
    enable = true;
    extraConfig = ''
      PasswordAuthentication no
      KbdInteractiveAuthentication no
      PubkeyAuthentication yes
      AuthenticationMethods publickey
      AuthorizedKeysFile none
      AllowUsers ilma4 malakhov
    '';
  };

  # Create /etc/zshrc that loads the nix-darwin environment.
  programs.zsh.enable = true; # default shell on catalina
  programs.zsh.enableGlobalCompInit = false;
  # nix-darwin's default /etc/zshrc runs `promptinit && prompt suse` and
  # `bashcompinit` on every interactive shell. Powerlevel10k replaces the prompt
  # anyway, so the prompt setup is wasted work; drop it. bashcompinit is only
  # needed for bash-style completion scripts, which this setup doesn't use.
  programs.zsh.promptInit = "";
  programs.zsh.enableBashCompletion = false;

  # Set Git commit hash for darwin-version.
  system.configurationRevision = inputs.self.rev or inputs.self.dirtyRev or "null";

  # Used for backwards compatibility, please read the changelog before changing.
  # $ darwin-rebuild changelog
  system.stateVersion = 5;

  # The platform the configuration will be used on.
  nixpkgs.hostPlatform = pkgs.system; # x86 or arm64, following pkgs
}
