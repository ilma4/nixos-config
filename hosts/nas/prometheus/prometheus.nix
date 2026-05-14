{
  config,
  constants,
  lib,
  pkgs,
  ...
}: let
  port = "9090";
  version = "v3.11.3";
  alertmanagerVersion = "v0.32.1";
  telegramMyIdSecret = constants.telegram.my-id-secret;
  notificationsApiKeySecret = constants.telegram.notifications-api-key-secret;
in let
  alertmanagerUidGid = "${toString config.users.users.alertmanager.uid}:${toString config.users.groups.alertmanager.gid}";
  prometheusCompose = ''
    services:
      prometheus:
        image: prom/prometheus:${version}
        user: "${toString config.users.users.prometheus.uid}:${toString config.users.groups.prometheus.gid}"
        container_name: prometheus
        volumes:
          - "''${CONFIG_FILE}:/etc/prometheus/prometheus.yml:ro"
          - "''${ALERTS_FILE}:/etc/prometheus/alerts.yml:ro"
          - "/srv/prometheus/data:/prometheus"

        network_mode: host

        labels:
          - "traefik.enable=true"
          - "traefik.http.routers.prometheus.rule=Host(`prometheus.ilma4.local`)"
          - "traefik.http.routers.prometheus.entrypoints=websecure"
          - "traefik.http.routers.prometheus.tls=true"
          - "traefik.http.services.prometheus.loadbalancer.server.port=${port}"

        restart: unless-stopped
  '';
  alertmanagerCompose = ''
    services:
      alertmanager:
        image: prom/alertmanager:${alertmanagerVersion}
        user: "${alertmanagerUidGid}"
        container_name: alertmanager
        volumes:
          - "${config.sops.templates."alertmanager.yml".path}:/etc/alertmanager/alertmanager.yml:ro"
          - "/srv/alertmanager:/alertmanager"
        command:
          - "--config.file=/etc/alertmanager/alertmanager.yml"
          - "--storage.path=/alertmanager"
          - "--web.listen-address=127.0.0.1:9093"
          - "--cluster.listen-address="
        network_mode: host
        restart: unless-stopped
  '';
in {
  services.prometheus.pushgateway = {
    enable = true;
    persistMetrics = true;
    extraFlags = [
      "--web.listen-address=127.0.0.1:9091"
    ];
  };

  services.prometheus.exporters.smartctl = {
    enable = true;
    listenAddress = "127.0.0.1";
    port = 9633;
    maxInterval = "5m";
    extraFlags = ["--smartctl.powermode-check=standby"];
  };

  sops.secrets.${telegramMyIdSecret} = {};
  sops.secrets.${notificationsApiKeySecret} = {};

  sops.templates."alertmanager.yml" = {
    content = ''
      route:
        receiver: telegram
        group_by:
          - alertname
          - host
          - repo
          - job
        group_wait: 30s
        group_interval: 5m
        repeat_interval: 12h

      receivers:
        - name: telegram
          telegram_configs:
            - bot_token: ${config.sops.placeholder.${notificationsApiKeySecret}}
              chat_id: ${config.sops.placeholder.${telegramMyIdSecret}}
              parse_mode: HTML
              send_resolved: true
    '';
    mode = "0400";
    owner = config.users.users.alertmanager.name;
    group = config.users.groups.alertmanager.name;
    restartUnits = ["alertmanager.service"];
  };

  users.users.alertmanager = {
    isSystemUser = true;
    uid = 806;
    group = config.users.groups.alertmanager.name;
  };
  users.groups.alertmanager = {
    gid = config.users.users.alertmanager.uid;
  };

  users.users.prometheus = {
    isSystemUser = true;
    uid = 802;
    group = config.users.groups.prometheus.name;
  };
  users.groups.prometheus = {
    gid = config.users.users.prometheus.uid;
  };

  systemd.tmpfiles.rules = [
    "d /srv/alertmanager 0700 ${config.users.users.alertmanager.name} ${config.users.groups.alertmanager.name} -"
    "d /srv/prometheus 0700 ${config.users.users.prometheus.name} ${config.users.groups.prometheus.name} -"
    "d /srv/prometheus/config 0700 ${config.users.users.prometheus.name} ${config.users.groups.prometheus.name} -"
    "d /srv/prometheus/data 0700 ${config.users.users.prometheus.name} ${config.users.groups.prometheus.name} -"
  ];

  dockerCompose.alertmanager = {
    composeText = alertmanagerCompose;
  };

  dockerCompose.prometheus = {
    composeText = prometheusCompose;
    environment = {
      ALERTS_FILE = "${./alerts.yml}";
      CONFIG_FILE = "${./config.yml}";
    };
  };

  networking.firewall.allowedTCPPorts = [
    (lib.toIntBase10 port)
  ];
}
