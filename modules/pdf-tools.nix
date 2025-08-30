{flake-location, ...}: {
  dockerCompose.stirling-pdf = {
    enable = true;
    composeFile = "${flake-location}/compose/stirling-pdf.yml";
  };
}
