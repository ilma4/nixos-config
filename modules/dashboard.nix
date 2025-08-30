{
  config,
  flake-location,
  ...
}: {
  users.users.homer = {
    isSystemUser = true;
    uid = 989;
    group = "homer";
  };
  users.groups.homer.gid = 985;

  dockerCompose.homer = {
    enable = true;
    composeFile = "${flake-location}/compose/homer.yml";
    environment = {
      UID_GID = "${toString config.users.users.homer.uid}:${toString config.users.groups.homer.gid}";
    };
  };
}
