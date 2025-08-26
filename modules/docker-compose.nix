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
      after = ["network-online.target" "podman.socket"];
      wants = ["network-online.target"];
      requires = ["podman.socket"];

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
}
