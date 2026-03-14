{
  pkgs,
  lib,
  ...
}: let
  src = pkgs.fetchFromGitHub {
    owner = "egor3f";
    repo = "rssalchemy";
    rev = "a839d87ee6b5517a40789990069317f1b03518c5";
    sha256 = "sha256-JHKmUxUPDJsnxPrCuPtVjG4B56NL/fV+C/BhRxNIxkE=";
  };

  composeYaml = pkgs.writeText "rssalchemy-compose.yml" ''
    services:
      webserver:
        build:
          context: "''${SOURCE_PATH}"
          dockerfile: deploy/Dockerfile_webserver
        env_file: "''${SOURCE_PATH}/deploy/.env"
        depends_on:
          - nats
        networks:
          - reverse_proxy
        expose:
          - "8080"
        container_name: rssalchemy-webserver
        restart: unless-stopped
        environment:
          - WEBSERVER_ADDRESS=0.0.0.0:8080

      worker:
        build:
          context: "''${SOURCE_PATH}"
          dockerfile: deploy/Dockerfile_worker
        env_file: "''${SOURCE_PATH}/deploy/.env"
        depends_on:
          - nats
          - redis
        ipc: host
        user: pwuser
        security_opt:
          - seccomp: "''${SOURCE_PATH}/deploy/seccomp_profile.json"
        deploy:
          replicas: 2
        restart: unless-stopped

      nats:
        image: docker.io/library/nats:2.10
        command: "-config /nats_config.conf"
        volumes:
          - "''${SOURCE_PATH}/deploy/nats_config.conf:/nats_config.conf:ro"
          - natsdata:/data
        restart: unless-stopped

      redis:
        image: docker.io/library/redis:7.4
        restart: unless-stopped

    volumes:
      natsdata:

    networks:
      reverse_proxy:
        external: true
  '';
in {
  dockerCompose.rssalchemy = {
    environment = {
      SOURCE_PATH = "${src}";
    };
    composeFile = composeYaml;
  };
}
