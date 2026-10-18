{
  lib,
  pkgs,
  pkgs-unstable,
  constants,
  ...
}: let
  vpnConfig = "/var/lib/amnezia/awg0.conf";
  endpointFile = "/run/qbt-vpn-endpoint.nft";
  prepareEndpoint = pkgs.writeShellScript "qbt-vpn-endpoint" ''
    set -euo pipefail
    umask 077
    ${pkgs.python3}/bin/python3 ${./qbittorrent-vpn-endpoint.py} ${vpnConfig} > ${endpointFile}
  '';
in {
  boot.kernelParams = ["net.ifnames=0"];
  # The stable pin predates AmneziaWG 3.1. Keep tools and kernel support in sync.
  boot.kernelPackages = pkgs-unstable.linuxPackages;
  microvm = {
    hypervisor = "qemu";
    vcpu = 2;
    # microvm.nix warns that QEMU hangs with exactly 2048 MiB.
    mem = 2049;
    interfaces = [
      {
        type = "tap";
        id = "qbt-tap";
        mac = "02:00:00:76:00:02";
        tap.vhost = true;
      }
    ];
    volumes = [
      {
        image = "state.img";
        mountPoint = "/";
        size = 8192;
      }
    ];
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
    interfaces.eth0.ipv4.addresses = [
      {
        address = "10.76.0.2";
        prefixLength = 30;
      }
    ];
    defaultGateway = {
      address = "10.76.0.1";
      interface = "eth0";
    };
    nameservers = ["1.1.1.1"];
    enableIPv6 = true;
    firewall = {
      enable = true;
      interfaces.eth0.allowedTCPPorts = [22 8080];
      checkReversePath = "loose";
    };
    wg-quick.interfaces.awg0 = {
      type = "amneziawg";
      configFile = vpnConfig;
      autostart = true;
    };
    nftables = {
      enable = true;
      # The endpoint comes from the private profile at runtime, never its keys.
      # nft's include lookup does not honor libredirect in the build checker.
      # Rewrite only the checked copy to an existing fixture; keep the runtime
      # include so the endpoint is still read from the private VPN profile.
      preCheckRuleset = ''
        substituteInPlace ruleset.conf \
          --replace-fail '${endpointFile}' '${pkgs.writeText "qbt-vpn-endpoint-check.nft" ''
          elements = { 192.0.2.1 . 51820 }
        ''}'
      '';
      tables.qbt-killswitch = {
        family = "inet";
        content = ''
          set vpnEndpoint {
            type ipv4_addr . inet_service
            include "${endpointFile}"
          }

          chain output {
            type filter hook output priority 0; policy drop;
            oifname "lo" accept
            oifname "awg0" accept
            oifname "eth0" ip daddr . udp dport @vpnEndpoint accept
            oifname "eth0" ip daddr 10.76.0.1 tcp sport { 22, 8080 } ct state established ct direction reply accept
            counter drop
          }

          chain forward {
            type filter hook forward priority 0; policy drop;
          }
        '';
      };
    };
  };
  # awg-quick's DNS setting uses resolvconf directly; no local proxy is needed.
  services.resolved.enable = lib.mkForce false;

  # Fail closed before networking, and retain the rules even on service stop.
  systemd.targets.network-pre.requires = ["nftables.service"];
  systemd.services.systemd-networkd = {
    requires = ["nftables.service"];
    after = ["nftables.service"];
  };
  systemd.services.nftables = {
    preStart = ''
      set -euo pipefail
      ${prepareEndpoint}
    '';
    serviceConfig = {
      ExecReload = lib.mkBefore ["${prepareEndpoint}"];
      ExecStop = lib.mkForce [];
    };
  };
  systemd.services.wg-quick-awg0 = {
    requires = ["nftables.service"];
    after = ["nftables.service"];
    preStart = ''
      set -euo pipefail
      ${pkgs.python3}/bin/python3 ${./qbittorrent-vpn-endpoint.py} ${vpnConfig} --check
      ${pkgs.systemd}/bin/systemctl reload nftables.service
    '';
  };
  systemd.tmpfiles.rules = ["d /var/lib/amnezia 0700 root root -"];
  environment.systemPackages = [pkgs.curl pkgs.tcpdump];

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
    wants = ["wg-quick-awg0.service"];
    after = ["nftables.service" "wg-quick-awg0.service"];
    # Merge managed settings; serverConfig would overwrite the entire
    # writable profile, including the WebUI password, on every service start.
    preStart = ''
      set -euo pipefail
      umask 077
      profile=/var/lib/qBittorrent/qBittorrent/config/qBittorrent.conf
      ${pkgs.crudini}/bin/crudini --set "$profile" BitTorrent 'Session\Interface' awg0
      ${pkgs.crudini}/bin/crudini --set "$profile" BitTorrent 'Session\InterfaceName' awg0
      ${pkgs.crudini}/bin/crudini --set "$profile" BitTorrent 'Session\InterfaceAddress' ""
      ${pkgs.crudini}/bin/crudini --set "$profile" Preferences 'WebUI\AuthSubnetWhitelistEnabled' true
      ${pkgs.crudini}/bin/crudini --set "$profile" Preferences 'WebUI\AuthSubnetWhitelist' 192.168.1.0/24
      ${pkgs.crudini}/bin/crudini --set "$profile" Preferences 'WebUI\LocalHostAuth' true
      ${pkgs.crudini}/bin/crudini --set "$profile" Preferences 'WebUI\ReverseProxySupportEnabled' true
      ${pkgs.crudini}/bin/crudini --set "$profile" Preferences 'WebUI\TrustedReverseProxiesList' 10.76.0.1
    '';
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
    openssh.authorizedKeys.keys = constants.main-pub-keys;
  };
  security.sudo.wheelNeedsPassword = false;
  system.stateVersion = "26.05";
}
