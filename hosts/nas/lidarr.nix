{
  config,
  pkgs,
  lib,
  ...
}: {
  users.users.lidarr = {
    isSystemUser = true;
    uid = 804;
    group = config.users.groups.lidarr.name;
  };
  users.groups.lidarr = {
    gid = 804;
  };

  dockerCompose.lidarr = {
    composeText = ''
      name: lidarr
      services:
        lidarr:
          container_name: lidarr
          image: ghcr.io/hotio/lidarr
          ports:
            - "8686:8686"
          environment:
            - PUID=${toString config.users.users.lidarr.uid}
            - PGID=${toString config.users.groups.lidarr.gid}
            - UMASK=002
          volumes:
            - /srv/lidarr/config/lidarr:/config
            - /srv/lidarr/data/lidarr:/data
            - /etc/localtime:/etc/localtime:ro



        # SABnzbd
        SABnzbd:
          image: ghcr.io/hotio/sabnzbd
          volumes:
            - /srv/lidarr/config/sabnzbd:/config
            - /srv/lidarr/data/usenet:/data/usenet
          environment:
            - PUID=${toString config.users.users.lidarr.uid}
            - PGID=${toString config.users.groups.lidarr.gid}
            - UMASK=002
          ports:
            - "8088:8080"


        # plex
        Plex:
          image: ghcr.io/hotio/plex
          volumes:
            - /srv/lidarr/config/plex:/config
            - /srv/lidarr/data/media:/data/media

          environment:
            - PUID=${toString config.users.users.lidarr.uid}
            - PGID=${toString config.users.groups.lidarr.gid}
            - UMASK=002
    '';
  };

  systemd.tmpfiles.rules = let
    uid = toString config.users.users.lidarr.uid;
    gid = toString config.users.groups.lidarr.gid;
  in [
    "d /srv/lidarr 0755 ${uid} ${gid} - -"
    "d /srv/lidarr/data 0755 ${uid} ${gid} - -"
    "d /srv/lidarr/data/torrents/music 0755 ${uid} ${gid} - -"
    "d /srv/lidarr/data/usenet/music 0755 ${uid} ${gid} - -"
  ];

  networking.firewall.allowedTCPPorts = [
    8686
    8088 # SABnzbd, TODO: remove
  ];
}
