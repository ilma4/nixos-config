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
      extraOptions = [
        "--network=host" # so UPnP mapping will work
        "--health-cmd=curl -fkLsS -m 2 127.0.0.1:8384/rest/noauth/health | grep -o --color=never OK || exit 1 "
        "--health-interval=1m0s"
        "--health-retries=3"
        "--health-start-period=20s"
        "--health-timeout=10s"
      ];
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
