{pkgs, ...}: let
  dir = pkgs.copyPathToStore ./.;
in {
  dockerCompose.immich = {
    composeFile = "${dir}/docker-compose.yml";
    envFile = "${dir}/.env";
    maxBodySize = "100000M";
  };

  systemd.services.immich.serviceConfig.WorkingDirectory = dir; # ./.
  networking.firewall.allowedTCPPorts = [2283];

  # TODO: setup proper UID and GID for postgres, currently it runs as 999:999, but directory is mounted as root:root causing permission issues
  systemd.tmpfiles.rules = [
    "d /srv/immich/library 700 root root -"
    "d /srv/immich/postgres 700 999 999 -"
  ];
}
