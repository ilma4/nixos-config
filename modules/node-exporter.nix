{
  config,
  lib,
  pkgs,
  ...
}:
with lib; let
  cfg = config.services.prometheus.node-exporter-docker;
in {
  options.services.prometheus.node-exporter-docker = {
    enable = mkEnableOption "Prometheus Node Exporter in Docker";

    port = mkOption {
      type = types.port;
      default = 9100;
      description = "Port to expose node-exporter on";
    };

    image = mkOption {
      type = types.str;
      default = "prom/node-exporter:latest";
      description = "Docker image to use for node-exporter";
    };

    user = mkOption {
      type = types.str;
      default = "node-exporter";
      description = "User to run the container as";
    };

    uid = mkOption {
      type = types.int;
      default = 803;
      description = "UID for the node-exporter user";
    };

    extraArgs = mkOption {
      type = types.listOf types.str;
      default = [
        "--path.rootfs=/host"
      ];
      description = "Extra arguments to pass to node-exporter (ignored when using dockerCompose)";
    };

    openFirewall = mkOption {
      type = types.bool;
      default = true;
      description = "Whether to open the firewall for the node-exporter port";
    };
  };

  config = mkIf cfg.enable {
    # Create user and group for node-exporter
    users.users.${cfg.user} = {
      isSystemUser = true;
      uid = cfg.uid;
      group = cfg.user;
      description = "Prometheus Node Exporter user";
    };

    users.groups.${cfg.user} = {
      gid = cfg.uid;
    };

    # Configure docker-compose service
    dockerCompose.node-exporter = {
      composeFile = "${lib.flake-location}/compose/node-exporter.yml";
      environment = {
        NODE_EXPORTER_IMAGE = cfg.image;
        NODE_EXPORTER_PORT = toString cfg.port;
        NODE_EXPORTER_UID = toString cfg.uid;
        NODE_EXPORTER_GID = toString cfg.uid;
      };
    };

    # Open firewall if requested
    networking.firewall.allowedTCPPorts = mkIf cfg.openFirewall [cfg.port];
  };
}
