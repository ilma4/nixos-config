{inputs, pkgs, pkgs-unstable, constants, ...}: {
  imports = [inputs.microvm.nixosModules.host];

  networking.interfaces.qbt-tap.ipv4.addresses = [{
    address = "10.76.0.1";
    prefixLength = 30;
  }];
  networking.nat = {
    enable = true;
    internalInterfaces = ["qbt-tap"];
  };
  networking.firewall.allowedTCPPorts = [8080];
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
    "d /home/ilma4/torrents 0775 1000 1000 -"
  ];

  microvm.vms.qbittorrent-amneziavpn = {
    specialArgs = {inherit pkgs-unstable constants;};
    config = import ./qbittorrent-amneziavpn-guest.nix;
  };
}
