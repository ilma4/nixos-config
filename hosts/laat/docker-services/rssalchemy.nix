{
  pkgs,
  lib,
  ...
}: let
  src = pkgs.fetchFromGitHub {
    owner = "egor3f";
    repo = "rssalchemy";
    rev = "a839d87ee6b5517a40789990069317f1b03518c5";
    sha256 = "sha256-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=";
  };

  composeYaml = pkgs.writeText "rssalchemy-compose.yml" ''
    services:
      webserver:
        build:
          context: ${src}
          dockerfile: deploy/Dockerfile_webserver
        env_file: ${src}/deploy/.env
        depends_on:
          - nats
        networks:
          - default
          - reverse_proxy
        expose:
          - "8080"
        container_name: rssalchemy-webserver
        restart: unless-stopped
        environment:
          - WEBSERVER_ADDRESS=0.0.0.0:8080

      worker:
        build:
          context: ${src}
          dockerfile: deploy/Dockerfile_worker
        env_file: ${src}/deploy/.env
        depends_on:
          - nats
          - redis
        ipc: host
        user: pwuser
        security_opt:
          - seccomp:${src}/deploy/seccomp_profile.json
        deploy:
          replicas: 2
        restart: unless-stopped

      nats:
        image: docker.io/library/nats:2.10
        command: "-config /nats_config.conf"
        volumes:
          - ${src}/deploy/nats_config.conf:/nats_config.conf:ro
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
    composeFile = composeYaml;
  };
}