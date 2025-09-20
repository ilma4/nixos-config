{
  config,
  lib,
  pkgs,
  ...
}: let
  prometheusCompose = pkgs.writeText "prometheus.yml" ''
    services:
      prometheus:
        image: prom/prometheus:latest
        user: "${toString config.users.users.prometheus.uid}:${toString config.users.groups.prometheus.gid}"
        container_name: prometheus
        volumes:
          - "$CONFIG_FILE:/etc/prometheus/prometheus.yml:ro"
          - "/srv/prometheus/data:/prometheus"
        expose:
          - "9090"
        networks:
          reverse_proxy:
        restart: unless-stopped

    networks:
      reverse_proxy:
        external: true
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
    9090
  ];
}
