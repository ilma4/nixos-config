{
  config,
  lib,
  ...
}:
with lib; let
  cfg = config.services.prometheus.node-exporter-docker;
  port = 9100;
in {
  options.services.prometheus.node-exporter-docker = {
    enable = mkEnableOption "Prometheus Node Exporter in Docker";
  };

  config = mkIf cfg.enable {
    # Create user and group for node-exporter
    users.users.node-exporter = {
      isSystemUser = true;
      uid = 803;
      group = "node-exporter";
      description = "Prometheus Node Exporter user";
    };

    users.groups.node-exporter = {
      gid = config.users.users.node-exporter.uid;
    };

    # Configure docker-compose service
    dockerCompose.node-exporter = {
      composeText = ''
        services:
          node-exporter:
            image: "prom/node-exporter:latest"
            user: "${toString config.users.users.node-exporter.uid}:${toString config.users.groups.node-exporter.gid}"
            container_name: "node-exporter"
            volumes:
              - "/:/host:ro,rslave"
              - "/etc/os-release:/host/etc/os-release:ro"
            command:
              - "--path.rootfs=/host"
              - "--path.udev.data=/host/run/udev/data"
              - "--web.listen-address=:${toString port}"
            pid: host
            network_mode: host
            read_only: true
            cap_drop:
              - ALL
            cap_add:
              - SYS_TIME
            restart: unless-stopped
      '';
    };

    # Open firewall if requested
    networking.firewall.allowedTCPPorts = [port];
  };
}
