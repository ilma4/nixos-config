{lib, ...}: {
  dockerCompose.syncthing = {
    composeText = builtins.readFile ../compose/syncthing.yml;
  };
  networking.firewall.allowedTCPPorts = [
    8334 # web interface
    22000
  ];
  networking.firewall.allowedUDPPorts = [
    22000
    21027
  ];
}
