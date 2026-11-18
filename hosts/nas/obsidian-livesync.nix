{
  config,
  constants,
  pkgs,
  ...
}: let
  obsidian = constants.nas.obsidian-livesync;
  dataDir = "/srv/obsidian-livesync";
  couchdbConfig = pkgs.writeText "obsidian-livesync.ini" ''
    [couchdb]
    single_node = true
    max_document_size = 50000000

    [cluster]
    n = 1

    [chttpd]
    enable_cors = true
    require_valid_user = true
    max_http_request_size = 4294967296

    [chttpd_auth]
    require_valid_user = true

    [httpd]
    WWW-Authenticate = Basic realm="couchdb"

    [cors]
    origins = app://obsidian.md,capacitor://localhost,http://localhost
    credentials = true
    headers = accept, authorization, content-type, origin, referer
    methods = GET, PUT, POST, HEAD, DELETE
    max_age = 3600
  '';
in {
  sops.secrets."obsidian-livesync/password" = {};
  sops.secrets."obsidian-livesync/admin-ini" = {
    uid = 5984;
    gid = 5984;
    mode = "0400";
    restartUnits = ["obsidian-livesync.service"];
  };

  systemd.tmpfiles.rules = ["d ${dataDir} 0700 5984 5984 -"];

  dockerCompose.obsidian-livesync.composeText = ''
    services:
      couchdb:
        image: docker.io/library/couchdb:3.5.3
        container_name: obsidian-livesync
        user: "5984:5984"
        restart: unless-stopped
        volumes:
          - ${dataDir}:/opt/couchdb/data
          - ${couchdbConfig}:/opt/couchdb/etc/local.d/00-livesync.ini:ro
          - ${config.sops.secrets."obsidian-livesync/admin-ini".path}:/opt/couchdb/etc/local.d/10-admin.ini:ro
        networks:
          reverse_proxy:
            ipv4_address: ${obsidian.ip}

    networks:
      reverse_proxy:
        external: true
  '';

  networking.nftables.tables.obsidian-livesync-proxy-only = {
    family = "inet";
    content = ''
      chain forward {
        type filter hook forward priority -10; policy accept;
        iifname "podman*" ip saddr ${constants.nas.traefik-ip} ip daddr ${obsidian.ip} tcp dport ${toString obsidian.port} accept
        ip daddr ${obsidian.ip} drop
      }
      chain postrouting {
        type filter hook postrouting priority srcnat - 5; policy accept;
        # Keep Tailscale's original peer address on HTTPS forwarded to Traefik.
        iifname "tailscale0" ip saddr 100.64.0.0/10 ip daddr ${constants.nas.traefik-ip} tcp dport 443 ct status dnat meta mark set meta mark & 0xff00ffff
      }
    '';
  };
}
