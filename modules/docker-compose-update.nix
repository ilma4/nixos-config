{
  lib,
  pkgs,
  config,
  ...
}: let
  cfg = config.dockerCompose;

  # Script to pull podman compose images and restart services with new images
  podmanComposePullScript = pkgs.writeShellScriptBin "podman-compose-pull" ''
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
        ${lib.concatStringsSep "\n        " (lib.mapAttrsToList (
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
  '';
in {
  options = {
    i4.dockerCompose.autoupdate.enable = lib.mkEnableOption "Enable automatic podman compose image updates";
  };
  config = lib.mkIf config.i4.dockerCompose.autoupdate.enable {
    systemd.services.podman-compose-pull-all = {
      description = "Daily podman compose image pull for all dockerCompose services";
      after = ["network-online.target" "podman.socket"];
      wants = ["network-online.target"];
      path = [pkgs.podman pkgs.podman-compose];
      serviceConfig = {
        Type = "oneshot";
        ExecStart = "${podmanComposePullScript}/bin/podman-compose-pull --all";
      };
    };

    systemd.timers.podman-compose-pull-all = {
      wantedBy = ["timers.target"];
      timerConfig = {
        OnCalendar = "05:00";
        Persistent = true;
        Unit = "podman-compose-pull-all.service";
      };
    };

    environment.systemPackages = [
      podmanComposePullScript
    ];
  };
}
