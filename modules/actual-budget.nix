{config, ...}: {
  users.users.actual-budget = {
    isSystemUser = true;
    uid = 800;
    group = "actual-budget";
  };
  users.groups.actual-budget.gid = config.users.users.actual-budget.uid;

  virtualisation.oci-containers.containers = {
    actual-budget = {
      image = "docker.io/actualbudget/actual-server:25.8.0-alpine"; # TODO: latest-alpine";
      volumes = [
        "/srv/actual-budget:/data:rw"
      ];
      ports = [
        "5006:5006/tcp"
      ];
      user = "${toString config.users.users.actual-budget.uid}:${toString config.users.groups.actual-budget.gid}";
      extraOptions = [
        "--health-cmd=node src/scripts/health-check.js"
        "--health-interval=1m0s"
        "--health-retries=3"
        "--health-start-period=20s"
        "--health-timeout=10s"
      ];
    };
  };

  networking.firewall.allowedTCPPorts = [
    5006
  ];
}
