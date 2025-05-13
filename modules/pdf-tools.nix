{...}: let
  stirling-pdf-version = "0.46.1-ultra-lite";
in {
  virtualisation.oci-containers.containers = {
    stirling-pdf = {
      # pdf tools
      image = "docker.io/stirlingtools/stirling-pdf:${stirling-pdf-version}";
      volumes = [
        "/etc/localtime:/etc/localtime:ro"
        "/srv/stirling-pdf/trainingData:/usr/share/tessdata"
        "/srv/stirling-pdf/extraConfigs:/configs"
        "/srv/stirling-pdf/logs:/logs"
        "/srv/stirling-pdf/pipeline:/pipeline"
      ];
      ports = ["8085:8080"];
      autoStart = true;
    };
  };
  networking.firewall.allowedTCPPorts = [
    8085 # stirling-pdf (pdf tools)
  ];
}
