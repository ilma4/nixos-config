{
  config,
  lib,
  flake-location,
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

    dockerCompose.qbittorrent = {
      composeFile = "${flake-location}/compose/qbittorrent.yml";
      environment = {
        GLUETUN_VERSION = gluetun-version;
        QBITTORRENT_VERSION = qbittorrent-version;
        WG_CONF_PATH = config.sops.secrets.${wg-conf}.path;
      };
    };

    networking.firewall.allowedTCPPorts = [
      8080 # qbittorrent web interface
    ];
  };
}
