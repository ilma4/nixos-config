# Auto-generated using compose2nix v0.3.1.
{
  pkgs,
  lib,
  ...
}:
let 
  paperless-version = "2.15.1";
  redis-version = "7";
  gotenberg-version = "8.19";
in
 {
  # Containers
  virtualisation.oci-containers.containers."paperless-broker" = {
    image = "docker.io/library/redis:${redis-version}";
    /*
    environmentFiles = [
      "/home/ilma4/paperless-ngx/docker-compose.env"
    ];
    */
    volumes = [
      "paperless_redisdata:/data:rw"
    ];
    log-driver = "journald";
    extraOptions = [
      "--network-alias=broker"
      "--network=paperless_default"
    ];
  };
  systemd.services."podman-paperless-broker" = {
    serviceConfig = {
      Restart = lib.mkOverride 90 "always";
    };
    after = [
      "podman-network-paperless_default.service"
      "podman-volume-paperless_redisdata.service"
    ];
    requires = [
      "podman-network-paperless_default.service"
      "podman-volume-paperless_redisdata.service"
    ];
    partOf = [
      "podman-compose-paperless-root.target"
    ];
    wantedBy = [
      "podman-compose-paperless-root.target"
    ];
  };
  /*
  virtualisation.oci-containers.containers."paperless-db" = {
    image = "docker.io/library/postgres:${postgres-version}";
    environment = {
      "POSTGRES_DB" = "paperless";
      "POSTGRES_PASSWORD" = "paperless";
      "POSTGRES_USER" = "paperless";
    };
    volumes = [
      "paperless_pgdata:/var/lib/postgresql/data:rw"
    ];
    log-driver = "journald";
    extraOptions = [
      "--network-alias=db"
      "--network=paperless_default"
    ];
  };
  */
  /*
  systemd.services."podman-paperless-db" = {
    serviceConfig = {
      Restart = lib.mkOverride 90 "always";
    };
    after = [
      "podman-network-paperless_default.service"
      "podman-volume-paperless_pgdata.service"
    ];
    requires = [
      "podman-network-paperless_default.service"
      "podman-volume-paperless_pgdata.service"
    ];
    partOf = [
      "podman-compose-paperless-root.target"
    ];
    wantedBy = [
      "podman-compose-paperless-root.target"
    ];
  };
  */
  virtualisation.oci-containers.containers."paperless-gotenberg" = {
    image = "docker.io/gotenberg/gotenberg:${gotenberg-version}";
    /*
    environmentFiles = [
      "/home/ilma4/paperless-ngx/docker-compose.env"
    ];
    */
    cmd = ["gotenberg" "--chromium-disable-javascript=true" "--chromium-allow-list=file:///tmp/.*"];
    log-driver = "journald";
    extraOptions = [
      "--network-alias=gotenberg"
      "--network=paperless_default"
    ];
  };
  systemd.services."podman-paperless-gotenberg" = {
    serviceConfig = {
      Restart = lib.mkOverride 90 "always";
    };
    after = [
      "podman-network-paperless_default.service"
    ];
    requires = [
      "podman-network-paperless_default.service"
    ];
    partOf = [
      "podman-compose-paperless-root.target"
    ];
    wantedBy = [
      "podman-compose-paperless-root.target"
    ];
  };
  virtualisation.oci-containers.containers."paperless-tika" = {
    image = "docker.io/apache/tika:latest";
    /*
    environmentFiles = [
      "/home/ilma4/paperless-ngx/docker-compose.env"
    ];
    */
    log-driver = "journald";
    extraOptions = [
      "--network-alias=tika"
      "--network=paperless_default"
    ];
  };
  systemd.services."podman-paperless-tika" = {
    serviceConfig = {
      Restart = lib.mkOverride 90 "always";
    };
    after = [
      "podman-network-paperless_default.service"
    ];
    requires = [
      "podman-network-paperless_default.service"
    ];
    partOf = [
      "podman-compose-paperless-root.target"
    ];
    wantedBy = [
      "podman-compose-paperless-root.target"
    ];
  };
  virtualisation.oci-containers.containers."paperless-webserver" = {
    image = "ghcr.io/paperless-ngx/paperless-ngx:${paperless-version}";
    environment = {
      "PAPERLESS_OCR_LANGUAGES" = "eng deu rus";
      "PAPERLESS_REDIS" = "redis://broker:6379";
      "PAPERLESS_TIKA_ENABLED" = "1";
      "PAPERLESS_TIKA_ENDPOINT" = "http://tika:9998";
      "PAPERLESS_TIKA_GOTENBERG_ENDPOINT" = "http://gotenberg:3000";
    };
    /*
    environmentFiles = [
      "/home/ilma4/paperless-ngx/docker-compose.env"
    ];
    */
    volumes = [
      "/srv/paperless-ngx/consume:/usr/src/paperless/consume:rw"
      "/srv/paperless-ngx/export:/usr/src/paperless/export:rw"

      "paperless_data:/usr/src/paperless/data:rw"
      "paperless_media:/usr/src/paperless/media:rw"
    ];
    ports = [
      "8000:8000/tcp"
    ];
    dependsOn = [
      "paperless-broker"
      "paperless-gotenberg"
      "paperless-tika"
    ];
    log-driver = "journald";
    extraOptions = [
      "--network-alias=webserver"
      "--network=paperless_default"
    ];
  };
  systemd.services."podman-paperless-webserver" = {
    serviceConfig = {
      Restart = lib.mkOverride 90 "always";
    };
    after = [
      "podman-network-paperless_default.service"
      "podman-volume-paperless_data.service"
      "podman-volume-paperless_media.service"
    ];
    requires = [
      "podman-network-paperless_default.service"
      "podman-volume-paperless_data.service"
      "podman-volume-paperless_media.service"
    ];
    partOf = [
      "podman-compose-paperless-root.target"
    ];
    wantedBy = [
      "podman-compose-paperless-root.target"
    ];
  };

  # Networks
  systemd.services."podman-network-paperless_default" = {
    path = [pkgs.podman];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStop = "podman network rm -f paperless_default";
    };
    script = ''
      podman network inspect paperless_default || podman network create paperless_default
    '';
    partOf = ["podman-compose-paperless-root.target"];
    wantedBy = ["podman-compose-paperless-root.target"];
  };

  # Volumes
  systemd.services."podman-volume-paperless_data" = {
    path = [pkgs.podman];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    script = ''
      podman volume inspect paperless_data || podman volume create paperless_data
    '';
    partOf = ["podman-compose-paperless-root.target"];
    wantedBy = ["podman-compose-paperless-root.target"];
  };
  systemd.services."podman-volume-paperless_media" = {
    path = [pkgs.podman];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    script = ''
      podman volume inspect paperless_media || podman volume create paperless_media
    '';
    partOf = ["podman-compose-paperless-root.target"];
    wantedBy = ["podman-compose-paperless-root.target"];
  };
  systemd.services."podman-volume-paperless_pgdata" = {
    path = [pkgs.podman];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    script = ''
      podman volume inspect paperless_pgdata || podman volume create paperless_pgdata
    '';
    partOf = ["podman-compose-paperless-root.target"];
    wantedBy = ["podman-compose-paperless-root.target"];
  };
  systemd.services."podman-volume-paperless_redisdata" = {
    path = [pkgs.podman];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    script = ''
      podman volume inspect paperless_redisdata || podman volume create paperless_redisdata
    '';
    partOf = ["podman-compose-paperless-root.target"];
    wantedBy = ["podman-compose-paperless-root.target"];
  };

  # Root service
  # When started, this will automatically create all resources and start
  # the containers. When stopped, this will teardown all resources.
  systemd.targets."podman-compose-paperless-root" = {
    unitConfig = {
      Description = "Root target generated by compose2nix.";
    };
    wantedBy = ["multi-user.target"];
  };
}
