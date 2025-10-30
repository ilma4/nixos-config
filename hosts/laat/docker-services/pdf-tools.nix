{pkgs, ...}: {
  dockerCompose.stirling-pdf = {
    enable = true;
    composeFile = pkgs.writeText "docker-compose.yml" ''
      name: stirling-pdf
      services:
        stirling-pdf:
          image: docker.io/stirlingtools/stirling-pdf:1.5.0-ultra-lite
          container_name: pdf-tools
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
          logging:
            driver: none
          restart: unless-stopped

      networks:
        reverse_proxy:
          external: true
    '';
  };
}
