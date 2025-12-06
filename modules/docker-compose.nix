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

  options = {
    i4.dockerComposeEnable = lib.mkEnableOption "Enable my docker compose services";

    dockerCompose = mkOption {
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
          maxBodySize = mkOption {
            type = types.str;
            default = "100M";
          };
        };
      }));
      default = {};
    };
  };

  config = lib.mkIf config.i4.dockerComposeEnable {
    systemd.tmpfiles.rules =
      [
        "d /var/compose-logs 0755 root root -"
      ]
      ++ lib.mapAttrsToList (name: _: "d /var/compose-logs/${name} 0755 root root -") (lib.filterAttrs (_: svc: svc.enable) cfg);

    services.logrotate = {
      enable = true;
      settings.composeLogs = {
        files = "/var/compose-logs/*/*.log";
        frequency = "monthly";
        rotate = 999999;
        compress = true;
        dateext = true;
        delaycompress = true;
        missingok = true;
        copytruncate = true;
        compresscmd = "${pkgs.zstd}/bin/zstd";
        compressext = ".zst";
      };
    };

    systemd.services =
      mapAttrs
      (name: svc: let
        composeFile =
          if (builtins.typeOf svc.composeFile == "path")
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
          StandardOutput = "append:/var/compose-logs/${name}/${name}.log";
          StandardError = "inherit";
        };

        wantedBy = ["multi-user.target"];
      })
      (lib.filterAttrs (name: svc: svc.enable) cfg);
  };
}
