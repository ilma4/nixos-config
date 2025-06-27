{config, ...}: {
  users.users.grafana = {
    isSystemUser = true;
    uid = 801;
    group = config.users.groups.grafana.name;
  };
  users.groups.grafana = {
    gid = config.users.users.grafana.uid;
  };

  virtualisation.oci-containers.containers.grafana = {
    image = "grafana/grafana:latest";
    ports = ["3000:3000"];
    user = "${toString config.users.users.grafana.uid}:${toString config.users.groups.grafana.gid}";
    volumes = ["/srv/grafana:/var/lib/grafana"];
  };
  systemd.tmpfiles.rules = [
    "d /srv/grafana 700 grafana grafana -"
  ];

  networking.firewall.allowedTCPPorts = [
    3000 # grafana
  ];
}
