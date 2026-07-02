{
  config,
  pkgs,
  ...
}: let
  immich-version = "v3.0.0";
  secretName = "immich/db_password";
  publicEnvFile = pkgs.copyPathToStore ./.env;
in {
  sops.secrets.${secretName} = {};

  sops.templates."immich-secret.env" = {
    content = ''
      DB_PASSWORD=${config.sops.placeholder.${secretName}}
      POSTGRES_PASSWORD=${config.sops.placeholder.${secretName}}
    '';
    mode = "0400";
    owner = "root";
    group = "root";
    restartUnits = ["immich.service"];
  };

  dockerCompose.immich = {
    composeText = builtins.readFile ./docker-compose.yml;
    envFile = publicEnvFile;
    environment = {
      IMMICH_VERSION = immich-version;
      IMMICH_ENV_FILE = toString publicEnvFile;
      IMMICH_SECRET_ENV_FILE = config.sops.templates."immich-secret.env".path;
    };
  };

  # networking.firewall.allowedTCPPorts = [2283];

  # TODO: setup proper UID and GID for postgres, currently it runs as 999:999, but directory is mounted as root:root causing permission issues
  systemd.tmpfiles.rules = [
    "d /srv/immich/library 700 root root -"
    "d /srv/immich/postgres 700 999 999 -"
  ];
}
