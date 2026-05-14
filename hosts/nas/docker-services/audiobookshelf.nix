{
  config,
  lib,
  pkgs,
  ...
}: let
  version = "2.34.0";

  srvDir = "/srv/audiobookshelf";
  configDir = "${srvDir}/config";
  metadataDir = "${srvDir}/metadata";
  audiobooksDir = "${srvDir}/audiobooks";
  podcastsDir = "${srvDir}/podcasts";

  composeText = ''
    services:
      audiobookshelf:
        image: ghcr.io/advplyr/audiobookshelf:${version}
        container_name: audiobookshelf
        labels:
          - "traefik.enable=true"
          - "traefik.http.routers.audiobookshelf.rule=Host(`audiobookshelf.ilma4.local`)"
          - "traefik.http.routers.audiobookshelf.entrypoints=websecure"
          - "traefik.http.routers.audiobookshelf.tls=true"
          - "traefik.http.services.audiobookshelf.loadbalancer.server.port=80"
        restart: unless-stopped

        networks:
          - reverse_proxy

        # nginx-reverse-proxy module discovers services on reverse_proxy with `expose`
        expose:
          - "80"
        ports:
          - "8222:80"

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
      composeText = composeText;
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
