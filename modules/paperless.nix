{
  pkgs,
  lib,
  ...
}: {
  # Containers
  dockerCompose.paperless.composeFile = "${lib.flake-location}/compose/paperless.yml";
  dockerCompose.paperless.environment = {
  };

  systemd.tmpfiles.rules = [
    "d /srv/paperless-ngx 750 ilma4 1000 -"
    "d /srv/paperless-ngx/export 750 ilma4 1000 -"
    "d /srv/paperless-ngx/consume 750 ilma4 1000 -"
    "d /srv/paperless-ngx/data 750 1000 1000 -"
    "d /srv/paperless-ngx/media 750 1000 1000 -"
  ];
}
