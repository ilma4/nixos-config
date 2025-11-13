{
  config,
  lib,
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
    composeFile = ../../../compose/grafana.yml;
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
