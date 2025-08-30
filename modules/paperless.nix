{
  pkgs,
  lib,
  flake-location,
  ...
}: {
  # Containers
  dockerCompose.paperless.composeFile = "${flake-location}/compose/paperless.yml";

  systemd.tmpfiles.rules = [
    "d /srv/paperless-ngx 755 ilma4 1000 -"
    "d /srv/paperless-ngx/export 755 ilma4 1000 -"
    "d /srv/paperless-ngx/consume 755 ilma4 1000 -"
    "d /srv/paperless-ngx/data 755 1000 1000 -"
    "d /srv/paperless-ngx/media 755 1000 1000 -"
  ];
}
