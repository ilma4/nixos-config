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
        composeFile = mkOption {type = types.str;};
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
      compose = "${pkgs.podman}/bin/podman compose --file ${svc.composeFile}";
    in {
      # TODO: require pdoman-network-reverse-proxy.service only when needed
      after = ["network-online.target" "podman.socket" "podman-network-reverse-proxy.service"];
      wants = ["network-online.target"];
      requires = ["podman.socket" "podman-network-reverse-proxy.service"];

      path = [pkgs.podman pkgs.podman-compose];
      restartTriggers = [
        pkgs.podman
        pkgs.podman-compose
        (builtins.readFile svc.composeFile)
      ];

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
