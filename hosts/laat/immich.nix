{
  pkgs,
  config,
  lib,
  ...
}: {
  dockerCompose.immich = {
    composeFile = ./immich/docker-compose.yml;
    envFile = ./immich/.env;
  };

  systemd.tmpfiles.rules = [
    "d /srv/immich/library 700 root root -"
    "d /srv/immich/postgres 700 root root -"
  ];
}
