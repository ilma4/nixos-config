{config, lib, pkgs, pkgs-unstable, constants, ...}: {
  boot.kernelParams = ["net.ifnames=0"];
  microvm = {
    hypervisor = "qemu";
    vcpu = 2;
    # microvm.nix warns that QEMU hangs with exactly 2048 MiB.
    mem = 2049;
    interfaces = [{
      type = "tap";
      id = "qbt-tap";
      mac = "02:00:00:76:00:02";
    }];
    volumes = [{
      image = "state.img";
      mountPoint = "/";
      size = 8192;
    }];
    shares = [
      {
        proto = "virtiofs";
        tag = "ro-store";
        source = "/nix/store";
        mountPoint = "/nix/.ro-store";
        readOnly = true;
      }
      {
        proto = "virtiofs";
        tag = "downloads";
        source = "/mnt/hdd/torrent";
        mountPoint = "/downloads";
      }
      {
        proto = "virtiofs";
        tag = "ssd-downloads";
        source = "/home/ilma4/torrents";
        mountPoint = "/ssd-downloads";
      }
    ];
  };
  networking = {
    useDHCP = false;
    useNetworkd = true;
    interfaces.eth0.ipv4.addresses = [{
      address = "10.76.0.2";
      prefixLength = 30;
    }];
    defaultGateway = {address = "10.76.0.1"; interface = "eth0";};
    nameservers = ["1.1.1.1"];
    enableIPv6 = false;
    firewall = {
      allowedTCPPorts = [22 8080];
      checkReversePath = "loose";
    };
    nftables = {
      enable = true;
      tables.qbt-killswitch = {
        family = "inet";
        content = ''
          chain output {
            type filter hook output priority -150; policy accept;
            meta skuid 1000 oifname "lo" accept
            meta skuid 1000 oifname "eth0" ip daddr 10.76.0.1 tcp sport 8080 ct state established accept
            meta skuid 1000 oifname "eth0" reject
          }
        '';
      };
    };
  };
  # Avoid a local DNS proxy bypassing the UID-based egress restriction.
  services.resolved.enable = lib.mkForce false;

  programs.amnezia-vpn = {
    enable = true;
    package = pkgs-unstable.amnezia-vpn;
  };
  services.qbittorrent = {
    enable = true;
    webuiPort = 8080;
    extraArgs = ["--confirm-legal-notice"];
    openFirewall = false;
  };
  users.users.qbittorrent.uid = 1000;
  users.groups.qbittorrent.gid = 1000;
  systemd.services.qbittorrent = {
    requires = ["nftables.service"];
    after = ["nftables.service"];
    serviceConfig.UMask = "0002";
  };
  services.openssh = {
    enable = true;
    settings = {
      PasswordAuthentication = false;
      KbdInteractiveAuthentication = false;
      PermitRootLogin = "no";
    };
  };
  users.users.vpn = {
    isNormalUser = true;
    uid = 1001;
    extraGroups = ["wheel"];
    linger = true;
    openssh.authorizedKeys.keys = constants.main-pub-keys;
  };
  security.sudo.wheelNeedsPassword = false;
  programs.sway.enable = true;
  environment.systemPackages = [pkgs.wayvnc];
  environment.etc."sway/vpn.conf".text = ''
    output HEADLESS-1 resolution 1280x800
    input * xkb_layout us
    exec ${pkgs.wayvnc}/bin/wayvnc 127.0.0.1 5900
    exec ${pkgs-unstable.amnezia-vpn}/bin/AmneziaVPN
  '';
  systemd.user.services.vpn-desktop = {
    description = "Headless VPN configuration desktop";
    wantedBy = ["default.target"];
    path = [pkgs.bash];
    unitConfig.ConditionUser = "vpn";
    environment = {
      WLR_BACKENDS = "headless";
      WLR_RENDERER = "pixman";
      WLR_LIBINPUT_NO_DEVICES = "1";
      QT_QPA_PLATFORM = "wayland";
    };
    serviceConfig = {
      ExecStart = "${config.programs.sway.package}/bin/sway --config /etc/sway/vpn.conf";
      Restart = "on-failure";
      RestartSec = 5;
    };
  };
  system.stateVersion = "26.05";
}
