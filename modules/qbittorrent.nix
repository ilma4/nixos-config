{
  config,
  lib,
  ...
}: let
  gluetun-version = "v3.40.0";
  qbittorrent-version = "5.0.4-r0-ls388";
in {
  options = {
    torrent = {
      wg-conf = lib.mkOption {
        type = lib.types.singleLineStr;
        description = "TODO";
        example = "ru-torrent-wg.conf";
      };
      downloads = lib.mkOption {
        type = lib.types.singleLineStr;
        description = "TODO";
        example = "/mnt/hdd";
      };
    };
  };
  config = let
    wg-conf = config.torrent.wg-conf;
  in {
    i4-encrypted-files = [wg-conf];

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
          "${config.sops.secrets.${wg-conf}.path}:/gluetun/wireguard/wg0.conf:ro"
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
        autoStart = lib.mkDefault false;
        extraOptions = ["--network=container:gluetun"];
      };
    };

    networking.firewall.allowedTCPPorts = [
      8080 # qbittorrent web interface
    ];
  };
}
