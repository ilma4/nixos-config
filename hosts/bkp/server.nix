{
  config,
  lib,
  pkgs,
  dotfiles,
  ...
}: {
  users.users = {
    homer = {
      isSystemUser = true;
      group = "homer";
    };
    homeassistant = {
      isSystemUser = true;
      group = "homeassistant";
    };
  };
  users.groups.homeassistant = {};
  users.groups.homer = {};

  virtualisation.podman = {
    enable = true;
    autoPrune.enable = true;
    defaultNetwork.settings = {
      # Required for container networking to be able to use names.
      dns_enabled = true;
    };
  };

  # Enable container name DNS for non-default Podman networks.
  # https://github.com/NixOS/nixpkgs/issues/226365
  networking.firewall.interfaces."podman+".allowedUDPPorts = [53];

  virtualisation.oci-containers.backend = "podman";

  virtualisation.oci-containers.containers = {
    homeassistant = {
      image = "ghcr.io/home-assistant/home-assistant:stable";
      volumes = [
        "/srv/homeassistant:/config"
        "/etc/localtime:/etc/localtime:ro"
        "/run/dbus:/run/dbus:ro"
      ];
      autoStart = true;
      extraOptions = ["--privileged" "--network=host"];
    };

    homer = {
      image = "b4bz/homer:latest";
      ports = ["80:8080"];
      volumes = ["${dotfiles}/homer:/www/assets:ro" "/etc/passwd:/etc/passwd:ro" "/etc/group:/etc/group:ro"];
      autoStart = true;
      user = "homer:homer";
      # hostname = "homer";
      # extraOptions = ["--network=nginx"];
    };

    syncthing = {
      image = "syncthing/syncthing:latest";
      ports = [
        "8384:8384"
        "22000:22000"
        "21027:21027/udp"
      ];
      volumes = [
        "/srv/syncthing:/var/syncthing"
        # "/mnt/hdd/Pictures/Oneplus10R:/var/syncthing/Pictures/Oneplus10R"
        "/srv/Pictures/Oneplus10R:/var/syncthing/Pictures/Oneplus10R"
        "/srv/Pictures/GalaxyS24:/var/syncthing/Pictures/GalaxyS24"
        "/etc/localtime:/etc/localtime:ro"
      ];
      hostname = "ilma4-bkp-syncthing";
      extraOptions = ["--network=host"]; # so UPnP mapping will work
      # TODO: healthcheck
    };

    gluetun = {
      image = "qmcgaw/gluetun:latest";
      environment = {
        "VPN_SERVICE_PROVIDER" = "custom";
        "VPN_TYPE" = "wireguard";
      };
      volumes = [
        "/etc/localtime:/etc/localtime:ro"
        "/home/ilma4/Docker/torrent/config/wireguard/wg0.conf:/gluetun/wireguard/wg0.conf:ro"
      ];
      ports = [
        "8080:8080" # qBittorrent
      ];
      hostname = "gluetun";
      autoStart = true;
      extraOptions = [
        "--device=/dev/net/tun:/dev/net/tun"
        "--cap-add=NET_ADMIN"
      ];
    };

    
    qbittorrent = {
      image = "linuxserver/qbittorrent:latest";
      volumes = [
        "/etc/localtime:/etc/localtime:ro"
        "/srv/qbittorrent/config:/config"
        "/mnt/hdd/torrent:/downloads"
      ];
      dependsOn = ["gluetun"];
      autoStart = true;
      extraOptions = ["--network=container:gluetun"];
    };
    

    /*
    nginx =  {
      image = "nginx:stable";
      ports = ["8080:8080"];
      volumes = [
        "/etc/localtime:/etc/localtime:ro"
        "${dotfiles}/nginx:/etc/nginx:ro"
        # "/etc/letsencrypt:/etc/letsencrypt:ro"
      ];
      autoStart = true;
      extraOptions = [
        "--network=qbittorrent"
      ];
    };
    */ 
  };

  services.avahi = {
    enable = true;
    nssmdns4 = true;
    nssmdns6 = true;
    ipv6 = true;
    publish = {
      enable = true;
      domain = true;
      addresses = true;
    };
    reflector = true;
  };

  /*
  systemd.timers.duck-dns-update = {
    enable = true;
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnBootSec="1min";
      OnUnitActiveSec="5min";
      Persistent="true";
      Unit = "duck-dns-update.service";
    };
    unitConfig = {
      Description="DuckDNS Update";
    };
  };

  systemd.services.duck-dns-update = {
    description="DuckDNS Update";
    serviceConfig  = {
      Type = "simple";
    };
    script=''echo url='https://www.duckdns.org/update?domains=ilma4-bkp&token=2a2144ab-3e5f-4288-8467-543ff76c751c&ip=' | ${pkgs.curl}/bin/curl -k -K -'';
  };
  */

  networking.firewall.allowedTCPPorts = [
    8123 # home-assistant
    80 # homer
    2283 # immich
    8080 # qbittorrent

    # syncthing
    8334
    22000
  ];

  networking.firewall.allowedUDPPorts = [
    #syncthing
    22000
    21027
  ];
}
