{
  lib,
  pkgs,
  config,
  ...
}: let
  inherit (lib) mkOption types mapAttrs;
  cfg = config.dockerCompose;
in {
  imports = [./docker-compose-update.nix];

  options.dockerCompose = mkOption {
    type = types.attrsOf (types.submodule (_: {
      options = {
        enable = mkOption {
          type = types.bool;
          default = true;
        };
        composeFile = mkOption {
          type = lib.types.path;
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

  config = {
    systemd.tmpfiles.rules = [
      "d /var/compose-logs 0755 root root -"
    ];
    systemd.services =
      mapAttrs
      (name: svc: let
        composeFile =
          if (lib.strings.hasPrefix "${lib.flake-location}" svc.composeFile)
          then pkgs.copyPathToStore svc.composeFile
          else svc.composeFile;
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
          StandardOutput = "append:/var/compose-logs/${name}.log";
          StandardError = "append:/var/compose-logs/${name}.log";
        };

        wantedBy = ["multi-user.target"];
      })
      (lib.filterAttrs (name: svc: svc.enable) cfg);
  };
}
