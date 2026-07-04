{config, ...}: {
  users.users.homer = {
    isSystemUser = true;
    uid = 989;
    group = "homer";
  };
  users.groups.homer.gid = 985;

  dockerCompose.homer = let
    uidGid = "${toString config.users.users.homer.uid}:${toString config.users.groups.homer.gid}";
  in {
    enable = true;
    environment = {
      ASSETS = "${./homer}";
    };
    composeText = ''
      name: "homer"
      services:
        homer:
          image: b4bz/homer:latest
          container_name: homer
          labels:
            - "traefik.enable=true"
            - "traefik.http.routers.dashboard.rule=Host(`dashboard.ilma4.local`)"
            - "traefik.http.routers.dashboard.entrypoints=websecure"
            - "traefik.http.routers.dashboard.tls=true"
            - "traefik.http.services.dashboard.loadbalancer.server.port=8080"
          expose:
            - "8080"

          networks:
            reverse_proxy:

          volumes:
            - /etc/localtime:/etc/localtime:ro
            - $ASSETS:/www/assets:ro

          user: "${uidGid}"
          restart: unless-stopped

      networks:
        reverse_proxy:
          external: true
    '';
  };
}
