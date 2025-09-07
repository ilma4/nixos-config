{
  pkgs,
  config,
  lib,
  ...
}: let
  dir = pkgs.copyPathToStore ./immich;
in {
  dockerCompose.immich = {
    composeFile = "${dir}/docker-compose.yml";
    envFile = "${dir}/.env";
  };

  systemd.services.immich.serviceConfig.WorkingDirectory = dir; # ./immich;

  systemd.tmpfiles.rules = [
    "d /srv/immich/library 700 root root -"
    "d /srv/immich/postgres 700 root root -"
  ];
}
