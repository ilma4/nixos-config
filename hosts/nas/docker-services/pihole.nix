{
  constants,
  pkgs,
  ...
}: let
  dataDir = "/srv/pihole";
  cfg = constants.nas.pihole;
  dnsRoute = "${cfg.lan-ip}/32 via ${cfg.host-ip}";
in {
  dockerCompose.pihole.composeText = ''
    name: pihole
    services:
      pihole:
        container_name: pihole
        image: pihole/pihole:latest
        environment:
          TZ: "Europe/Berlin"
          FTLCONF_webserver_api_password: "correct horse battery staple"
          FTLCONF_dns_listeningMode: "all"
          FTLCONF_misc_dnsmasq_lines: |-
            address=/ilma4.home.arpa/${constants.nas.lan-ip}
            address=/news.ycombinator.com/0.0.0.0
            address=/habr.com/0.0.0.0
            address=/www.phoronix.com/0.0.0.0
            address=/meduza.io/0.0.0.0
        volumes:
          - "${dataDir}:/etc/pihole"
          # Uncomment if you’re migrating from v5 and need dnsmasq configs
          # - './etc-dnsmasq.d:/etc/dnsmasq.d'
        cap_add:
          - NET_ADMIN
          - SYS_TIME
          - SYS_NICE
        restart: unless-stopped
        networks:
          pihole_net:
            ipv4_address: ${cfg.lan-ip}
            ipv6_address: "fd00:abcd::200"
          pihole_host:
            ipv4_address: ${cfg.host-ip}

    networks:
      # A second interface bypasses macvlan's isolation from the NAS host.
      pihole_host:
        driver: bridge
        x-podman.disable_dns: true
        driver_opts:
          no_default_route: "true"
        ipam:
          config:
            - subnet: ${cfg.host-subnet}
              gateway: ${cfg.host-gateway}
      pihole_net:
        driver: macvlan
        driver_opts:
          parent: enp2s0 # <-- change this to your LAN NIC
        ipam:
          config:
            - subnet: 192.168.1.0/24 # <-- your LAN subnet
              gateway: 192.168.1.1 # <-- your LAN gateway (router)
              ip_range: ${cfg.lan-ip}/32 # <-- allocate just one IP for Pi-hole
            - subnet: "fd00:abcd::/64"
              gateway: "fd00:abcd::1"
              ip_range: "fd00:abcd::200/128"

  '';

  services.tailscale = {
    useRoutingFeatures = "server";
    extraSetFlags = [
      # Less specific than the home LAN /24 so local clients use the LAN.
      # The tailnet policy restricts this route to the NAS and Pi-hole.
      "--advertise-routes=192.168.0.0/23"
      "--snat-subnet-routes=true"
    ];
  };

  systemd.services.pihole = {
    # Pi-hole owns the destination address on its LAN interface, but the NAS
    # reaches it via the bridge. Tailscale's SNAT supplies the return path.
    postStart = ''
      set -euo pipefail
      ${pkgs.iproute2}/bin/ip route replace ${dnsRoute}
    '';
    postStop = ''
      set -euo pipefail
      # Network removal may already have removed the route.
      if ${pkgs.iproute2}/bin/ip route show exact ${cfg.lan-ip}/32 | ${pkgs.gnugrep}/bin/grep -q 'via ${cfg.host-ip}'; then
        ${pkgs.iproute2}/bin/ip route del ${dnsRoute}
      fi
    '';
  };

  systemd.tmpfiles.rules = [
    "d ${dataDir} 0755 root root -"
  ];
}
