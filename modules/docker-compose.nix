{
  lib,
  pkgs,
  config,
  ...
}: let
  inherit (lib) mkOption types mapAttrs;
  cfg = config.dockerCompose;
  enabledComposeServices = lib.filterAttrs (_: svc: svc.enable) cfg;
in {
  imports = [
    ./docker-compose-journalctl.nix
    ./docker-compose-update.nix
  ];

  options = {
    i4.dockerComposeEnable = lib.mkEnableOption "Enable my docker compose services";

    dockerCompose = mkOption {
      type = types.attrsOf (types.submodule (_: {
        options = {
          enable = mkOption {
            type = types.bool;
            default = true;
          };
          composeText = mkOption {
            type = lib.types.str;
          };
          composeFile = mkOption {
            type = lib.types.nullOr lib.types.path;
            default = null;
          };
          environment = mkOption {
            type = types.attrsOf types.str;
            default = {};
          };
          envFile = mkOption {
            type = lib.types.nullOr lib.types.path;
            default = null;
          };
        };
      }));
      default = {};
    };
  };

  config = lib.mkIf config.i4.dockerComposeEnable {
    systemd.targets.docker-compose = {
      description = "Target for all docker-compose services";
      wantedBy = ["multi-user.target"];
    };

    systemd.services =
      mapAttrs
      (name: svc: let
        composeFile =
          if svc.composeFile != null
          then svc.composeFile
          else (pkgs.writeText "docker-compose-${name}.yml" svc.composeText);
        compose =
          "${pkgs.podman}/bin/podman compose --file ${composeFile}"
          + (
            if (svc.envFile != null)
            then " --env-file '${svc.envFile}'"
            else ""
          );
      in {
        # TODO: require pdoman-network-reverse_proxy.service only when needed
        after = ["network-online.target" "podman.socket" "${config.systemd.services.podman-network-reverse_proxy.name}"];
        wants = ["network-online.target"];
        requires = ["podman.socket" "${config.systemd.services.podman-network-reverse_proxy.name}"];

        path = [pkgs.podman pkgs.podman-compose];
        restartTriggers = [
          pkgs.podman
          pkgs.podman-compose
          composeFile
        ];

        environment = svc.environment;

        serviceConfig = {
          Type = "simple";
          ExecStart = "${compose} up --pull";
          ExecStop = "${compose} down";
          Restart = "always";
        };

        wantedBy = ["docker-compose.target"];
        partOf = ["docker-compose.target"];
      })
      enabledComposeServices;
  };
}
