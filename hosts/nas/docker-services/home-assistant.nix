{pkgs, ...}: let
  CONFIG_DIR = "/srv/homeassistant";
  home-assistant-version = "2026.5.4";
in {
  users.users.homeassistant = {
    isSystemUser = true;
    uid = 990;
    group = "homeassistant";
  };
  users.groups.homeassistant.gid = 986;

  dockerCompose.home-assistant.composeText = ''
    name: home-assistant
    services:
      home-assistant:
        container_name: home-assistant
        image: "ghcr.io/home-assistant/home-assistant:${home-assistant-version}"
        volumes:
          - ${CONFIG_DIR}:/config
          - /etc/localtime:/etc/localtime:ro
          - /run/dbus:/run/dbus:ro
        labels:
          - "traefik.enable=true"
          - "traefik.http.routers.home-assistant.rule=Host(`home-assistant.ilma4.local`)"
          - "traefik.http.routers.home-assistant.entrypoints=websecure"
          - "traefik.http.routers.home-assistant.tls=true"
          - "traefik.http.services.home-assistant.loadbalancer.server.port=8123"
        network_mode: host
        restart: unless-stopped
        privileged: true
  '';

  networking.firewall.allowedTCPPorts = [8123];

  systemd.tmpfiles.rules = [
    "d /srv/homeassistant 0755 root root -"
  ];
}
