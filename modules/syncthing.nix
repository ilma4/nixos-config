{...}: {
  dockerCompose.syncthing = {
    composeText = builtins.readFile ../dockerCompose/syncthing.yml;
  };
  networking.firewall.allowedTCPPorts = [
    8384 # web interface
    22000
  ];
  networking.firewall.allowedUDPPorts = [
    22000
    21027
  ];
}
