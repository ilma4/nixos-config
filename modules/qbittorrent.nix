{
  config,
  secrets,
  ...
}: let
  gluetun-version = "v3.40.0";
  qbittorrent-version = "5.0.4-r0-ls388";
in {
  i4-encrypted-files = ["ru-torrent-wg.conf"];

  virtualisation.oci-containers.containers = {
    # VPN for qbittorrent
    gluetun = {
      image = "qmcgaw/gluetun:${gluetun-version}";
      environment = {
        "VPN_SERVICE_PROVIDER" = "custom";
        "VPN_TYPE" = "wireguard";
      };
      volumes = [
        "/etc/localtime:/etc/localtime:ro"
        "${config.sops.secrets."ru-torrent-wg.conf".path}:/gluetun/wireguard/wg0.conf:ro"
      ];
      ports = [
        "8080:8080" # qBittorrent web interface
      ];
      hostname = "gluetun";
      autoStart = true;
      extraOptions = [
        "--device=/dev/net/tun:/dev/net/tun"
        "--cap-add=NET_ADMIN"
      ];
    };

    qbittorrent = {
      image = "linuxserver/qbittorrent:${qbittorrent-version}";
      volumes = [
        "/etc/localtime:/etc/localtime:ro"
        "/srv/qbittorrent/config:/config"
        "/mnt/hdd/torrent:/downloads"
      ];
      dependsOn = ["gluetun"];
      autoStart = false;
      extraOptions = ["--network=container:gluetun"];
    };
  };

  networking.firewall.allowedTCPPorts = [
    8080 # qbittorrent web interface
  ];
}
