{
  lib,
  pkgs,
  config,
  ...
}: let
  inherit (lib) mkOption types mapAttrs;
  cfg = config.dockerCompose;
in {
  options.dockerCompose = mkOption {
    type = types.attrsOf (types.submodule (_: {
      options = {
        enable = mkOption {
          type = types.bool;
          default = true;
        };
        composeFile = mkOption {
          type = types.nullOr types.str;
          default = null;
        };
        environment = mkOption {
          type = types.attrsOf types.str;
          default = {};
        };
      };
    }));
    default = {};
  };

  config.systemd.services =
    mapAttrs
    (name: svc: let
      composeFilePath =
        if svc.composeFile != null
        then svc.composeFile
        else (pkgs.writeText "${name}-compose.yaml" svc.composeStr);
      compose = "${pkgs.podman}/bin/podman compose --file ${composeFilePath}";
    in {
      # TODO: require pdoman-network-reverse_proxy.service only when needed
      after = ["network-online.target" "podman.socket" "${config.systemd.services.podman-network-reverse_proxy.name}"];
      wants = ["network-online.target"];
      requires = ["podman.socket" "${config.systemd.services.podman-network-reverse_proxy.name}"];

      path = [pkgs.podman pkgs.podman-compose];
      restartTriggers =
        [
          pkgs.podman
          pkgs.podman-compose
        ]
        ++ (
          if svc.composeFile != null
          then [(builtins.readFile svc.composeFile)]
          else [composeFilePath]
        );

      environment = svc.environment;

      serviceConfig = {
        Type = "simple";
        ExecStart = "${compose} up --pull";
        ExecStop = "${compose} down";
        Restart = "always";
      };

      wantedBy = ["multi-user.target"];
    })
    (lib.filterAttrs (name: svc: svc.enable) cfg);

  # TODO: script to update images (and restart if needed)
  # TODO: systemd-timer checking for image updates and restarting services
}
