{
  flake-location,
  config,
  ...
}: {
  users.users.actual-budget = {
    isSystemUser = true;
    uid = 800;
    group = "actual-budget";
  };
  users.groups.actual-budget.gid = config.users.users.actual-budget.uid;

  dockerCompose.actual-budget.composeFile = "${flake-location}/compose/actual-budget.yml";
  dockerCompose.actual-budget.environment = {
    UID_GID = "${toString config.users.users.actual-budget.uid}:${toString config.users.groups.actual-budget.gid}";
  };

  systemd.tmpfiles.rules = [
    "d /srv/actual-budget 0755 actual-budget actual-budget -"
  ];
}
