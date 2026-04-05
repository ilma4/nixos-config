{
  config,
  lib,
  ...
}: {
  options = {
    torrent = {
      wg-conf = lib.mkOption {
        type = lib.types.path;
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
    # i4-encrypted-files = [wg-conf];

    dockerCompose.qbittorrent = {
      enable = false; # todo: fix issues with secrets
      composeText = builtins.readFile ../../../dockerCompose/qbittorrent.yml;
      # enable = false;
      environment = {
        # TODO: fix
        # WG_CONF_PATH = config.sops.secrets.${wg-conf}.path;
      };
    };

    networking.firewall.allowedTCPPorts = [
      8080 # qbittorrent web interface
    ];
  };
}
