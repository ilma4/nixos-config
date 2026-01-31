{pkgs, ...}: let
  version = "2025.11.1";
in {
  dockerCompose.pihole.composeFile = pkgs.writeText "docker-compose.yml" ''
    name: pihole
    services:
      pihole:
        container_name: pihole
        # TODO: update version
        image: pihole/pihole:${version}
        environment:
          TZ: "Europe/Berlin"
          FTLCONF_webserver_api_password: "correct horse battery staple"
          FTLCONF_dns_listeningMode: "all"
        volumes:
          - "/srv/pihole:/etc/pihole"
          # Uncomment if you’re migrating from v5 and need dnsmasq configs
          # - './etc-dnsmasq.d:/etc/dnsmasq.d'
        cap_add:
          - NET_ADMIN
          - SYS_TIME
          - SYS_NICE
        restart: unless-stopped
        logging:
          driver: none
        networks:
          pihole_net:
            ipv4_address: 192.168.1.200 # <-- pick a free static IP on your LAN
            ipv6_address: "fd00:abcd::200"

    networks:
      pihole_net:
        driver: macvlan
        driver_opts:
          parent: enp2s0 # <-- change this to your LAN NIC
        ipam:
          config:
            - subnet: 192.168.1.0/24 # <-- your LAN subnet
              gateway: 192.168.1.1 # <-- your LAN gateway (router)
              ip_range: 192.168.1.200/32 # <-- allocate just one IP for Pi-hole
            - subnet: "fd00:abcd::/64"
              gateway: "fd00:abcd::1"
              ip_range: "fd00:abcd::200/128"

  '';
}
