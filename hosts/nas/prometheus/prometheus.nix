{
  config,
  lib,
  pkgs,
  ...
}: let
  port = "9090";
  version = "v3.10.0";
in let
  prometheusCompose = pkgs.writeText "prometheus.yml" ''
    services:
      prometheus:
        image: prom/prometheus:${version}
        user: "${toString config.users.users.prometheus.uid}:${toString config.users.groups.prometheus.gid}"
        container_name: prometheus
        volumes:
          - "${"$"}{CONFIG_FILE:-/aaa}:/etc/prometheus/prometheus.yml:ro"
          - "/srv/prometheus/data:/prometheus"

        network_mode: host

        labels:
          - "traefik.enable=true"
          - "traefik.http.routers.home-assistant.rule=Host(`prometheus.ilma4.local`)"
          - "traefik.http.routers.home-assistant.entrypoints=websecure"
          - "traefik.http.routers.home-assistant.tls=true"
          - "traefik.http.services.home-assistant.loadbalancer.server.port=${port}"

        restart: unless-stopped
  '';
in {
  users.users.prometheus = {
    isSystemUser = true;
    uid = 802;
    group = config.users.groups.prometheus.name;
  };
  users.groups.prometheus = {
    gid = config.users.users.prometheus.uid;
  };

  systemd.tmpfiles.rules = [
    "d /srv/prometheus 0700 ${config.users.users.prometheus.name} ${config.users.groups.prometheus.name} -"
    "d /srv/prometheus/config 0700 ${config.users.users.prometheus.name} ${config.users.groups.prometheus.name} -"
    "d /srv/prometheus/data 0700 ${config.users.users.prometheus.name} ${config.users.groups.prometheus.name} -"
  ];

  dockerCompose.prometheus = {
    composeFile = prometheusCompose;
    environment = {
      CONFIG_FILE = "${./config.yml}";
    };
  };

  networking.firewall.allowedTCPPorts = [
    (lib.toIntBase10 port)
  ];
}
