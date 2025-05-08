{...}: {
  virtualisation.oci-containers.containers = {
    syncthing = {
      image = "syncthing/syncthing:latest";
      ports = [
        "8384:8384"
        "22000:22000"
        "21027:21027/udp"
      ];
      volumes = [
        "/srv/syncthing:/var/syncthing"
        "/etc/localtime:/etc/localtime:ro"
      ];
      hostname = "ilma4-bkp-syncthing";
      extraOptions = ["--network=host"]; # so UPnP mapping will work
      # TODO: healthcheck
    };
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
