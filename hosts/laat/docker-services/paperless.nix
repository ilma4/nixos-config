{pkgs, ...}: let
  redis-version = "8";
  paperless-version = "2.19.2";
  tika-version = "3.2.3.0-full";
in {
  # Containers
  dockerCompose.paperless.composeFile = pkgs.writeText "docker-compose.yml" ''
    name: paperless-ngx
    services:
      broker:
        image: docker.io/library/redis:${redis-version}
        restart: unless-stopped
        logging:
          driver: none
        volumes:
          - redisdata:/data
      webserver:
        image: ghcr.io/paperless-ngx/paperless-ngx:${paperless-version}
        restart: unless-stopped
        logging:
          driver: none
        container_name: paperless
        depends_on:
          - broker
          - gotenberg
          - tika
        expose:
          - "8000"
        ports:
          - "8000:8000"
        networks:
          reverse_proxy:

        volumes:
          # TODO pass `/srv/paperless-ngx` as env-var
          - /srv/paperless-ngx/data:/usr/src/paperless/data
          - /srv/paperless-ngx/media:/usr/src/paperless/media
          - /srv/paperless-ngx/export:/usr/src/paperless/export
          - /srv/paperless-ngx/consume:/usr/src/paperless/consume
        # env_file: docker-compose.env # https://github.com/paperless-ngx/paperless-ngx/blob/main/docker/compose/docker-compose.env
        environment:
          PAPERLESS_OCR_LANGUAGES: "eng deu rus"

          PAPERLESS_REDIS: redis://broker:6379
          PAPERLESS_TIKA_ENABLED: 1
          PAPERLESS_TIKA_GOTENBERG_ENDPOINT: http://gotenberg:3000
          PAPERLESS_TIKA_ENDPOINT: http://tika:9998

          PAPERLESS_URL: "https://paperless.ilma4.local"
          PAPERLESS_USE_X_FORWARD_PORT: "true"
          PAPERLESS_USE_X_FORWARD_HOST: "true"
          PAPERLESS_PROXY_SSL_HEADER: '["HTTP_X_FORWARDED_PROTO", "https"]'
      gotenberg:
        image: docker.io/gotenberg/gotenberg:8.20
        restart: unless-stopped
        logging:
          driver: none
        # The gotenberg chromium route is used to convert .eml files. We do not
        # want to allow external content like tracking pixels or even javascript.
        command:
          - "gotenberg"
          - "--chromium-disable-javascript=true"
          - "--chromium-allow-list=file:///tmp/.*"
      tika:
        image: docker.io/apache/tika:${tika-version}
        restart: unless-stopped
        logging:
          driver: none
    volumes:
      data:
      media:
      redisdata:

    networks:
      reverse_proxy:
        external: true
  '';

  dockerCompose.paperless.environment = {
  };

  networking.firewall.allowedTCPPorts = [8000];

  systemd.tmpfiles.rules = [
    "d /srv/paperless-ngx 750 ilma4 1000 -"
    "d /srv/paperless-ngx/export 750 ilma4 1000 -"
    "d /srv/paperless-ngx/consume 750 ilma4 1000 -"
    "d /srv/paperless-ngx/data 750 1000 1000 -"
    "d /srv/paperless-ngx/media 750 1000 1000 -"
  ];
}
