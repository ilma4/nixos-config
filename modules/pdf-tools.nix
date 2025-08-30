{flake-location, ...}: {
  dockerCompose.stirling-pdf = {
    enable = true;
    composeFile = "${flake-location}/compose/stirling-pdf.yml";
  };

  networking.firewall.allowedTCPPorts = [
    8085 # stirling-pdf (pdf tools)
  ];
}
