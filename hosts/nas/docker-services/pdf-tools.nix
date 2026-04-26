{pkgs, ...}: let
  version = "2.10.0";
in {
  dockerCompose.stirling-pdf = {
    enable = true;
    composeText = ''
      name: stirling-pdf
      services:
        stirling-pdf:
          image: docker.io/stirlingtools/stirling-pdf:${version}-ultra-lite
          container_name: pdf-tools
          labels:
            - "traefik.enable=true"
            - "traefik.http.routers.pdf-tools.rule=Host(`pdf-tools.ilma4.local`)"
            - "traefik.http.routers.pdf-tools.entrypoints=websecure"
            - "traefik.http.routers.pdf-tools.tls=true"
            - "traefik.http.services.pdf-tools.loadbalancer.server.port=8080"
          expose:
            - "8080"

          networks:
            reverse_proxy:

          volumes:
            - /etc/localtime:/etc/localtime:ro
            - /srv/stirling-pdf/trainingData:/usr/share/tessdata
            - /srv/stirling-pdf/extraConfigs:/configs
            - /srv/stirling-pdf/logs:/logs
            - /srv/stirling-pdf/pipeline:/pipeline
          restart: unless-stopped

      networks:
        reverse_proxy:
          external: true
    '';
  };
}
