{config}: {
  users.users.grafana = {
    systemUser = true;
    uid = 801;
    group = config.users.users.grafana.group.name;
  };
  users.groups.grafana = {
    gid = config.users.users.grafana.uid;
  };

  # virtualisation.oci-containers.grafana = {
  # image = "grafana/grafana:latest";
  # ports = [8080];
  # volumes = ["/srv-test/grafana"];
  # };
  systemd.tmpfiles.rules = [
    "d /srv-test/grafana 700 grafana grafana"
  ];
}
