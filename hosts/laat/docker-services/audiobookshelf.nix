{
  config,
  lib,
  pkgs,
  ...
}: let
  version = "2.32.1";

  srvDir = "/srv/audiobookshelf";
  configDir = "${srvDir}/config";
  metadataDir = "${srvDir}/metadata";
  audiobooksDir = "${srvDir}/audiobooks";
  podcastsDir = "${srvDir}/podcasts";

  composeFile = pkgs.writeText "audiobookshelf.yml" ''
    services:
      audiobookshelf:
        image: ghcr.io/advplyr/audiobookshelf:${version}
        container_name: audiobookshelf
        restart: unless-stopped

        networks:
          - reverse_proxy

        # nginx-reverse-proxy module discovers services on reverse_proxy with `expose`
        expose:
          - "80"

        environment:
          - TZ=Europe/Berlin

        volumes:
          - ${configDir}:/config
          - ${metadataDir}:/metadata

          - ${audiobooksDir}:/audiobooks
          - ${podcastsDir}:/podcasts

    networks:
      reverse_proxy:
        external: true
  '';
in {
  config = {
    dockerCompose.audiobookshelf = {
      composeFile = composeFile;
      maxBodySize = "10240M";
    };

    systemd.tmpfiles.rules = [
      "d ${srvDir} 0755 root root -"
      "d ${configDir} 0755 root root -"
      "d ${metadataDir} 0755 root root -"
      "d ${audiobooksDir} 0755 root root -"
      "d ${podcastsDir} 0755 root root -"
    ];
  };
}
