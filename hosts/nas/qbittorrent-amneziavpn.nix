{
  inputs,
  pkgs,
  pkgs-unstable,
  constants,
  ...
}: {
  imports = [inputs.microvm.nixosModules.host];

  # Prefer lower idle power over the wake-up latency benefit of KVM polling.
  boot.extraModprobeConfig = ''
    options kvm halt_poll_ns=0
  '';

  networking.interfaces.qbt-tap.ipv4.addresses = [
    {
      address = "10.76.0.1";
      prefixLength = 30;
    }
  ];
  networking.nat = {
    enable = true;
    internalInterfaces = ["qbt-tap"];
  };
  networking.firewall.allowedTCPPorts = [8080];
  # The TCP relay hides the original peer. Only Traefik may supply forwarded
  # client addresses; otherwise an external client could forge the LAN bypass.
  networking.nftables = {
    enable = true;
    tables.qbt-webui-proxy-only = {
      family = "inet";
      content = ''
        chain input {
          type filter hook input priority -10; policy accept;
          iifname "lo" tcp dport 8080 accept
          ip saddr ${constants.nas.traefik-ip} tcp dport 8080 accept
          tcp dport 8080 drop
        }
      '';
    };
  };
  systemd.sockets.qbt-webui = {
    wantedBy = ["sockets.target"];
    listenStreams = ["8080"];
  };
  systemd.services.qbt-webui = {
    requires = ["qbt-webui.socket"];
    after = ["qbt-webui.socket"];
    serviceConfig = {
      ExecStart = "${pkgs.systemd}/lib/systemd/systemd-socket-proxyd 10.76.0.2:8080";
      DynamicUser = true;
    };
  };
  systemd.tmpfiles.rules = [
    "d /mnt/hdd/torrent 0775 1000 1000 -"
    "d /mnt/ssd/torrent 0775 1000 1000 -"
  ];

  # Do not start the share on the root disk if the SSD is unavailable.
  systemd.services."microvm-virtiofsd@qbittorrent-amneziavpn".unitConfig.RequiresMountsFor = ["/mnt/ssd/torrent"];

  microvm.vms.qbittorrent-amneziavpn = {
    # wg-quick selects this package internally as well as installing awg/awg-quick.
    pkgs = pkgs.extend (_: _: {inherit (pkgs-unstable) amneziawg-tools;});
    specialArgs = {inherit pkgs-unstable constants;};
    config = import ./qbittorrent-amneziavpn-guest.nix;
  };
}
