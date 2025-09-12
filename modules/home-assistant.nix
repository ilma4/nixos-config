{pkgs, ...}: let
  CONFIG_DIR = "/srv/homeassistant";
in {
  users.users.homeassistant = {
    isSystemUser = true;
    uid = 990;
    group = "homeassistant";
  };
  users.groups.homeassistant.gid = 986;

  dockerCompose.home-assistant.composeFile = pkgs.writeText "docker-compose.yml" ''
    name: home-assistant
    services:
      home-assistant:
        container_name: home-assistant
        image: "ghcr.io/home-assistant/home-assistant:stable"
        volumes:
          - ${CONFIG_DIR}:/config
          - /etc/localtime:/etc/localtime:ro
          - /run/dbus:/run/dbus:ro
        labels:
          - "local.ilma4.customResolve=10.20.0.1:8123" # reverse-proxy will use this IP address to resolve container instead of the container's hostname
        network_mode: host
        restart: unless-stopped
        privileged: true
  '';

  networking.firewall.allowedTCPPorts = [8123];

  systemd.tmpfiles.rules = [
    "/srv/homeassistant 0755 root root -"
  ];
}
