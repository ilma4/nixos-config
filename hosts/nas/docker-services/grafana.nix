{
  config,
  lib,
  pkgs,
  ...
}: let
  version = "12.3.5";
  port = "3000";
in {
  users.users.grafana = {
    isSystemUser = true;
    uid = 801;
    group = config.users.groups.grafana.name;
  };
  users.groups.grafana = {
    gid = config.users.users.grafana.uid;
  };

  dockerCompose.grafana = {
    composeText = ''
      services:
        grafana:
          image: grafana/grafana:${version}
          ports:
            - "${port}:${port}"
          user: "''${GRAFANA_UID}:''${GRAFANA_GID}"
          volumes:
            - "/srv/grafana:/var/lib/grafana"
          network_mode: host
          labels:
            - "traefik.enable=true"
            - "traefik.http.routers.grafana.rule=Host(`grafana.ilma4.local`)"
            - "traefik.http.routers.grafana.entrypoints=websecure"
            - "traefik.http.routers.grafana.tls=true"
            - "traefik.http.services.grafana.loadbalancer.server.port=${port}"
          restart: unless-stopped
    '';
    environment = {
      GRAFANA_UID = toString config.users.users.grafana.uid;
      GRAFANA_GID = toString config.users.groups.grafana.gid;
    };
  };
  systemd.tmpfiles.rules = [
    "d /srv/grafana 700 grafana grafana -"
  ];

  networking.firewall.allowedTCPPorts = [
    (lib.toIntBase10 port)
  ];
}
