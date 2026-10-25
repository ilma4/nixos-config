{
  constants,
  pkgs,
  ...
}: let
  cypht = constants.mail-archive.cypht;
  port = toString cypht.port;
  phpFpmConfig = pkgs.writeText "cypht-php-fpm.conf" ''
    [www]
    listen = 127.0.0.1:9000
    listen.allowed_clients = 127.0.0.1
  '';
  nginxConfig = pkgs.writeText "cypht-nginx.conf" ''
    user www-data;
    worker_processes auto;
    pid /run/nginx.pid;
    events { worker_connections 768; }
    http {
      include /etc/nginx/mime.types;
      default_type application/octet-stream;
      access_log /dev/stdout;
      error_log /dev/stderr;
      set_real_ip_from ${constants.nas.traefik-ip};
      real_ip_header X-Real-IP;
      # Keep access control tied to the connection peer, before real-IP rewriting.
      geo $realip_remote_addr $allowed_peer {
        default 0;
        127.0.0.1 1;
        ${constants.nas.traefik-ip} 1;
      }
      server {
        listen 127.0.0.1:${port};
        listen ${cypht.proxyGateway}:${port};
        server_name ${cypht.host};
        if ($allowed_peer = 0) { return 403; }
        root /var/www;
        index index.php;
        client_max_body_size 60M;
        location / { try_files $uri /index.php$is_args$args; }
        location ~ \.php$ {
          try_files $uri =404;
          include fastcgi_params;
          fastcgi_param SCRIPT_FILENAME $document_root$fastcgi_script_name;
          fastcgi_param HTTPS on;
          fastcgi_pass 127.0.0.1:9000;
        }
      }
    }
  '';
in {
  dockerCompose.cypht.composeText = ''
    services:
      cypht:
        image: docker.io/cypht/cypht:2.13.0@sha256:52d41a0ebfd347c2e2d33c42a0f8171c8a15564243b42a597694825f0cef3125
        container_name: cypht
        network_mode: host
        restart: unless-stopped
        environment:
          AUTH_TYPE: IMAP
          IMAP_AUTH_NAME: Local mail archive
          IMAP_AUTH_SERVER: 127.0.0.1
          IMAP_AUTH_PORT: "1144"
          IMAP_AUTH_TLS: "false"
          DB_DRIVER: sqlite
          DB_NAME: /var/lib/hm3/db/cypht.sqlite
          DB_USER: ""
          DB_PASS: ""
          SESSION_TYPE: PHP
          USER_CONFIG_TYPE: file
          USER_SETTINGS_DIR: /var/lib/hm3/users
          ATTACHMENT_DIR: /var/lib/hm3/attachments
          ENABLE_REDIS: "false"
          ENABLE_MEMCACHED: "false"
          DEFAULT_SMTP_SERVER: ""
          CYPHT_MODULES: core,imap,imap_folders,contacts,local_contacts,profiles,themes,history,advanced_search,saved_searches,brute_force
        volumes:
          - ${cypht.data}:/var/lib/hm3
          - ${nginxConfig}:/etc/nginx/nginx.conf:ro
          - ${phpFpmConfig}:/usr/local/etc/php-fpm.d/zzzz-mail-archive.conf:ro
        healthcheck:
          test: ["CMD", "curl", "--fail", "--silent", "http://127.0.0.1:${port}/"]
          interval: 30s
          timeout: 10s
          start_period: 60s
          retries: 3
  '';
  systemd.tmpfiles.rules = [
    # The image runs PHP as www-data (33); no other host account receives access.
    "d ${cypht.data} 0700 33 33 -"
    "d ${cypht.data}/db 0700 33 33 -"
    "d ${cypht.data}/users 0700 33 33 -"
    "d ${cypht.data}/attachments 0700 33 33 -"
    "f ${cypht.data}/db/cypht.sqlite 0600 33 33 -"
  ];
  systemd.services.cypht = {
    after = ["dovecot.service" "systemd-tmpfiles-setup.service"];
    requires = ["dovecot.service"];
  };
  networking.firewall.allowedTCPPorts = [cypht.port];
  networking.nftables.tables.mail-archive-proxy-only = {
    family = "inet";
    content = ''
      chain input {
        type filter hook input priority -10; policy accept;
        iifname "lo" tcp dport ${port} accept
        ip saddr ${constants.nas.traefik-ip} tcp dport ${port} accept
        tcp dport ${port} drop
      }
    '';
  };
}
