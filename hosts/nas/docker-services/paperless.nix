{config, pkgs, ...}: let
  paperlessSecretKey = "paperless/secret_key";
  valkey-version = "9-alpine";
  paperless-version = "3.2.1";
  tika-version = "3.3.1.0";
  gotenberg-version = "8.37";
  llamaProxyPort = 18080;
in {
  # Containers
  dockerCompose.paperless = {
    composeText = ''
    name: paperless-ngx
    services:
      broker:
        image: docker.io/valkey/valkey:${valkey-version}
        restart: unless-stopped
        volumes:
          - valkeydata:/data
      webserver:
        image: ghcr.io/paperless-ngx/paperless-ngx:${paperless-version}
        restart: unless-stopped
        container_name: paperless
        labels:
          - "traefik.enable=true"
          - "traefik.http.routers.paperless.rule=Host(`paperless.ilma4.home.arpa`)"
          - "traefik.http.routers.paperless.entrypoints=websecure"
          - "traefik.http.routers.paperless.tls=true"
          - "traefik.docker.network=reverse_proxy"
          - "traefik.http.services.paperless.loadbalancer.server.port=8000"
        depends_on:
          - broker
          - gotenberg
          - tika
        expose:
          - "8000"
        networks:
          default:
          reverse_proxy:

        volumes:
          - /srv/paperless-ngx/data:/usr/src/paperless/data
          - /srv/paperless-ngx/media:/usr/src/paperless/media
          - /srv/paperless-ngx/export:/usr/src/paperless/export
          - /srv/paperless-ngx/consume:/usr/src/paperless/consume
        env_file:
          - ${config.sops.templates."paperless.env".path}
        environment:
          PAPERLESS_OCR_LANGUAGES: "eng deu rus"

          PAPERLESS_REDIS: redis://broker:6379
          PAPERLESS_TIKA_ENABLED: 1
          PAPERLESS_TIKA_GOTENBERG_ENDPOINT: http://gotenberg:3000
          PAPERLESS_TIKA_ENDPOINT: http://tika:9998

          PAPERLESS_URL: "https://paperless.ilma4.home.arpa"
          PAPERLESS_USE_X_FORWARD_PORT: "true"
          PAPERLESS_USE_X_FORWARD_HOST: "true"
          PAPERLESS_PROXY_SSL_HEADER: '["HTTP_X_FORWARDED_PROTO", "https"]'
          PAPERLESS_OCR_ROTATE_PAGES: "true"

          PAPERLESS_AI_ENABLED: "true"
          PAPERLESS_AI_LLM_BACKEND: "openai-like"
          PAPERLESS_AI_LLM_ENDPOINT: "http://host.containers.internal:${toString llamaProxyPort}/v1"
          PAPERLESS_AI_LLM_MODEL: "gemma-4-12B-it-qat-UD-Q4_K_XL"
          # The OpenAI client requires a key; this private llama.cpp server has no auth.
          PAPERLESS_AI_LLM_API_KEY: "unused"
          # Allow time for on-demand model loading and CPU/GPU inference.
          PAPERLESS_AI_LLM_REQUEST_TIMEOUT: "600"
          # Keep embeddings on the NAS; Gemma is a generation model.
          PAPERLESS_AI_LLM_EMBEDDING_BACKEND: "huggingface"
          PAPERLESS_AI_LLM_EMBEDDING_MODEL: "intfloat/multilingual-e5-small"
          # Stay below the embedding model's 512-token input limit.
          PAPERLESS_AI_LLM_EMBEDDING_CHUNK_SIZE: "384"
      gotenberg:
        image: docker.io/gotenberg/gotenberg:${gotenberg-version}
        restart: unless-stopped
        # The gotenberg chromium route is used to convert .eml files. We do not
        # want to allow external content like tracking pixels or even javascript.
        command:
          - "gotenberg"
          - "--chromium-disable-javascript=true"
          - "--chromium-allow-list=file:///tmp/.*"
      tika:
        image: docker.io/apache/tika:${tika-version}
        restart: unless-stopped
    volumes:
      data:
      media:
      valkeydata:

    networks:
      default:
      reverse_proxy:
        external: true
    '';
  };

  # Resolve msi-modern.local through the host's mDNS resolver on each connection.
  systemd.sockets.paperless-llama = {
    wantedBy = ["sockets.target"];
    listenStreams = ["10.20.0.1:${toString llamaProxyPort}"];
    # The reverse_proxy bridge is created after sockets.target.
    socketConfig.FreeBind = true;
  };
  systemd.services.paperless-llama = {
    requires = ["paperless-llama.socket"];
    after = ["avahi-daemon.service"];
    wants = ["avahi-daemon.service"];
    serviceConfig = {
      ExecStart = "${pkgs.systemd}/lib/systemd/systemd-socket-proxyd msi-modern.local:8080";
      DynamicUser = true;
    };
  };

  sops.secrets.${paperlessSecretKey} = {};

  sops.templates."paperless.env" = {
    content = ''
      PAPERLESS_SECRET_KEY=${config.sops.placeholder.${paperlessSecretKey}}
    '';
    mode = "0400";
    owner = "root";
    group = "root";
    restartUnits = ["paperless.service"];
  };

  networking.firewall.allowedTCPPorts = [8000];
  networking.firewall.extraInputRules = ''
    ip saddr 10.20.0.0/24 ip daddr 10.20.0.1 tcp dport ${toString llamaProxyPort} accept
  '';

  systemd.tmpfiles.rules = [
    "d /srv/paperless-ngx 750 ilma4 1000 -"
    "d /srv/paperless-ngx/export 750 ilma4 1000 -"
    "d /srv/paperless-ngx/consume 750 ilma4 1000 -"
    "d /srv/paperless-ngx/data 750 1000 1000 -"
    "d /srv/paperless-ngx/media 750 1000 1000 -"
  ];
}
