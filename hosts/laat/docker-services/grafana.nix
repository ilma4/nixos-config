{
  config,
  pkgs,
  ...
}: {
  users.users.grafana = {
    isSystemUser = true;
    uid = 801;
    group = config.users.groups.grafana.name;
  };
  users.groups.grafana = {
    gid = config.users.users.grafana.uid;
  };

  dockerCompose.grafana = {
    composeFile = pkgs.writeText "docker-compose.yml" ''
      services:
        grafana:
          image: grafana/grafana:latest
          ports:
            - "3000:3000"
          user: "''${GRAFANA_UID}:''${GRAFANA_GID}"
          volumes:
            - "/srv/grafana:/var/lib/grafana"
          network_mode: host
          logging:
            driver: none
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
    3000 # grafana
  ];
}
