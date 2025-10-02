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
        };

        wantedBy = ["multi-user.target"];
      })
      (lib.filterAttrs (name: svc: svc.enable) cfg);

    environment.systemPackages = [
      (pkgs.writeShellScriptBin "podman-compose-pull" ''
        set -euo pipefail

        if [ "$EUID" -ne 0 ] && [ "${"$"}{NOROOT:-0}" != "1" ]; then
            echo "This script must be run as root or with NOROOT=1" >&2
            exit 1
        fi

        # Auto-generated from dockerCompose config. Pulls images for services and restarts them if new images were found.
        # Usage:
        #   podman-compose-pull <service-name>
        #   podman-compose-pull --all

        SERVICES="${lib.concatStringsSep " " (lib.attrNames (lib.filterAttrs (_: svc: svc.enable) cfg))}"
        export PATH="${pkgs.podman}/bin:${pkgs.docker-compose}/bin:$PATH"

        usage() {
          echo "Usage: podman-compose-pull <service-name>|--all"
          echo ""
          echo "Pulls images for docker-compose services and restarts them if new images were found."
          echo ""
          echo "Available services:"
          if [ -n "$SERVICES" ]; then
            for s in $SERVICES; do
              echo "  - $s"
            done
          else
            echo "  (no enabled services)"
          fi
        }

        pull_one() {
          local name="$1"
          case "$name" in
            ${lib.concatStringsSep "\n            " (lib.mapAttrsToList (
          name: svc: let
            composeFile =
              if (lib.strings.hasPrefix "${lib.flake-location}" svc.composeFile)
              then pkgs.copyPathToStore svc.composeFile
              else svc.composeFile;
            envArg =
              if (svc.envFile != null)
              then " --env-file '${svc.envFile}'"
              else "";
          in "${name})
              echo \"Pulling images for ${name}...\"
              pull_output=$(${pkgs.podman}/bin/podman compose --file ${composeFile}${envArg} pull 2>&1)
              echo \"$pull_output\"
              if echo \"$pull_output\" | grep -q -E \"(Pulling|Downloaded|digest:|newer image)\"; then
                echo \"New images detected for ${name}, restarting service...\"
                systemctl restart \"${name}.service\"
                echo \"Service ${name} restarted successfully\"
              else
                echo \"No new images for ${name}\"
              fi
              ;;"
        ) (lib.filterAttrs (_: svc: svc.enable) cfg))}
            *)
              echo "Unknown service: $name" >&2
              echo "" >&2
              usage >&2
              return 1
              ;;
          esac
        }

        main() {
            if [ "${"$"}{1:-}" = "--all" ]; then
            if [ -z "$SERVICES" ]; then
              echo "No services configured."
              exit 0
            fi
            for s in $SERVICES; do
              pull_one "$s"
            done
          elif [ -n "$${1:-}" ]; then
            pull_one "$1"
          else
            usage
            exit 1
          fi
        }

        main "$@"
      '')
    ];
  };
  # TODO: systemd-timer checking for image updates and restarting services
}
