{pkgs, ...}: let
  version = "2.13.1";
  srvDir = "/srv/stirling-pdf";
  trainingDataDir = "${srvDir}/trainingData";
  extraConfigsDir = "${srvDir}/extraConfigs";
  logsDir = "${srvDir}/logs";
  pipelineDir = "${srvDir}/pipeline";
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
            - ${trainingDataDir}:/usr/share/tessdata
            - ${extraConfigsDir}:/configs
            - ${logsDir}:/logs
            - ${pipelineDir}:/pipeline
          restart: unless-stopped

      networks:
        reverse_proxy:
          external: true
    '';
  };

  systemd.tmpfiles.rules = [
    "d ${srvDir} 0755 root root -"
    "d ${trainingDataDir} 0755 root root -"
    "d ${extraConfigsDir} 0755 root root -"
    "d ${logsDir} 0755 root root -"
    "d ${pipelineDir} 0755 root root -"
  ];
}
