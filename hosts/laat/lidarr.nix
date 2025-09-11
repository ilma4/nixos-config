{
  config,
  pkgs,
  lib,
  ...
}: {
  users.users.lidarr = {
    isSystemUser = true;
    uid = 803;
    group = config.users.groups.lidarr.name;
  };
  users.groups.lidarr = {
    gid = 803;
  };

  dockerCompose.lidarr = {
    composeFile = pkgs.writeText "lidarr-compose.yml" ''
      name: lidarr
      services:
        lidarr:
          container_name: lidarr
          image: ghcr.io/hotio/lidarr
          ports:
            - "8686:8686"
          environment:
            - PUID=${config.users.users.lidarr.uid}
            - PGID=${config.users.users.lidarr.gid}
            - UMASK=002
          volumes:
            - /srv/lidarr/config/lidarr:/config
            - /srv/lidarr/data:/data
            - /etc/localtime:/etc/localtime:ro
    '';
  };

  systemd.tmpfiles.rules = [
    "d /srv/lidarr ${config.users.users.lidarr.uid} ${config.users.users.lidarr.gid} - -"
  ];

  networking.firewall.allowedTCPPorts = [8686];
}
