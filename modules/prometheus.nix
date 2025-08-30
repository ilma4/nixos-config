{
  config,
  flake-location,
  ...
}: {
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
    composeFile = "${flake-location}/compose/prometheus.yml";
    environment = {
      PROMETHEUS_UID = toString config.users.users.prometheus.uid;
      PROMETHEUS_GID = toString config.users.groups.prometheus.gid;
      CONFIG_FILE = "${flake-location}/dotfiles/prometheus.yml";
    };
  };

  networking.firewall.allowedTCPPorts = [
    9090
  ];
}
