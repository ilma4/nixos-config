{lib, ...}: {
  dockerCompose.stirling-pdf = {
    enable = true;
    composeFile = "${lib.flake-location}/compose/stirling-pdf.yml";
  };
}
