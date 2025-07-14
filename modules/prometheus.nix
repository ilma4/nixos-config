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

  virtualisation.oci-containers.containers.prometheus = {
    image = "prom/prometheus:latest";
    user = "${toString config.users.users.prometheus.uid}:${toString config.users.groups.prometheus.gid}";
    volumes = [
      "${flake-location}/dotfiles/prometheus.yml:/etc/prometheus/prometheus.yml"
      "/srv/prometheus/data:/prometheus"
    ];
    ports = [
      "9090:9090"
    ];
    extraOptions = [
      "--network=host"
    ];
  };

  networking.firewall.allowedTCPPorts = [
    9090
  ];
}
