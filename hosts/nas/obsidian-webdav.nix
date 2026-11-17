{
  config,
  constants,
  pkgs,
  ...
}: let
  service = "obsidian-webdav";
  gateway = constants.nas.reverse-proxy-gateway;
  port = constants.nas.obsidian-webdav.port;
  htpasswd = config.sops.secrets.obsidian-webdav-htpasswd.path;
in {
  users.groups.${service} = {};
  users.users.${service} = {
    isSystemUser = true;
    group = service;
  };

  sops.secrets.obsidian-webdav-htpasswd = {
    owner = service;
    group = service;
    mode = "0400";
    restartUnits = ["${service}.service"];
  };

  systemd.services.${service} = {
    description = "Obsidian WebDAV server";
    wantedBy = ["multi-user.target"];
    after = ["podman-network-reverse_proxy.service" "nftables.service"];
    requires = ["podman-network-reverse_proxy.service" "nftables.service"];
    serviceConfig = {
      User = service;
      Group = service;
      StateDirectory = service;
      StateDirectoryMode = "0700";
      ExecStart = ''
        ${pkgs.rclone}/bin/rclone serve webdav /var/lib/${service} \
          --addr ${gateway}:${toString port} \
          --htpasswd ${htpasswd} \
          --disable-dir-list --disable-zip
      '';
      Restart = "on-failure";
      RestartSec = "5s";
      NoNewPrivileges = true;
      PrivateTmp = true;
      ProtectHome = true;
      ProtectSystem = "strict";
      UMask = "0077";
    };
  };

  networking.firewall.allowedTCPPorts = [port];
  networking.nftables.tables.obsidian-webdav-proxy-only = {
    family = "inet";
    content = ''
      chain input {
        type filter hook input priority -10; policy accept;
        iifname "podman*" ip saddr ${constants.nas.traefik-ip} ip daddr ${gateway} tcp dport ${toString port} accept
        tcp dport ${toString port} drop
      }
      chain postrouting {
        type filter hook postrouting priority srcnat - 5; policy accept;
        # Podman DNAT forwards HTTPS to Traefik. Clear Tailscale's subnet-router
        # mark for this path so its masquerade rule preserves the peer address.
        iifname "tailscale0" ip saddr 100.64.0.0/10 ip daddr ${constants.nas.traefik-ip} tcp dport 443 ct status dnat meta mark set meta mark & 0xff00ffff
      }
    '';
  };
}
