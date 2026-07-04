/*
Weekly auto-update for docker-compose services. Pulls the registry images of
every enabled compose project one by one and restarts a project's systemd unit
when a pull brought a new image (the unit's `down`/`up --pull` cycle then
recreates the containers from it). Stops early when a registry rate limit is
hit, so remaining pulls don't burn through the limit as well.
*/
{
  lib,
  myLib,
  pkgs,
  config,
  ...
}: let
  enabledComposeServices = lib.filterAttrs (_: svc: svc.enable) config.dockerCompose;
  # Registry image references of one compose project. Images referencing
  # environment variables (e.g. immich's `${IMMICH_VERSION:-release}`) are only
  # resolved from env files at runtime, so they cannot be pulled by name here
  # and are skipped.
  imagesOf = svc:
    lib.pipe ((myLib.yaml.fromYaml svc.composeText).services or {}) [
      (lib.mapAttrsToList (_: service: service.image or null))
      (lib.filter (image: image != null && !(lib.hasInfix "$" image)))
      lib.unique
    ];
  serviceImages =
    lib.filterAttrs (_: images: images != [])
    (lib.mapAttrs (_: imagesOf) enabledComposeServices);
in {
  config = lib.mkIf config.i4.dockerComposeEnable {
    systemd.services.docker-compose-auto-update = {
      description = "Pull new images for docker-compose services and restart the updated ones";
      after = ["network-online.target"];
      wants = ["network-online.target"];
      path = [pkgs.podman config.systemd.package];
      serviceConfig = {
        Type = "oneshot";
        # Type=oneshot has no start timeout by default; bound it so a hung
        # pull cannot wedge the run forever.
        TimeoutStartSec = "1h";
      };
      script = ''
        set -euo pipefail

        failed=0
        restarted=()

        is_rate_limited() {
          grep -qiE 'toomanyrequests|too many requests|rate ?limit' <<<"$1"
        }

        image_id() {
          podman image inspect --format '{{.Id}}' "$1" 2>/dev/null || echo none
        }

        update_service() {
          local unit="$1"
          shift
          local restart=0 pull_failed=0 was_failed=0 image before out
          # A failed unit may be fixed by an update (e.g. it crash-loops on a
          # bad image), so keep pulling for it; skip only units that are
          # inactive on purpose.
          if systemctl is-failed --quiet "$unit.service"; then
            was_failed=1
          elif ! systemctl is-active --quiet "$unit.service"; then
            echo "$unit: not active; skipping"
            return 0
          fi
          for image in "$@"; do
            before=$(image_id "$image")
            echo "$unit: pulling $image"
            if ! out=$(podman pull "$image" 2>&1); then
              printf '%s\n' "$out" >&2
              if is_rate_limited "$out"; then
                echo "$unit: registry rate limit reached; stopping early" >&2
                exit 1
              fi
              echo "$unit: failed to pull $image" >&2
              failed=1
              pull_failed=1
              continue
            fi
            if [[ "$before" != "$(image_id "$image")" ]]; then
              restart=1
            fi
          done
          # Restarting with a partially pulled project would `down` a running
          # stack whose `up --pull` then re-hits the failing registry.
          if [[ "$pull_failed" == 1 ]]; then
            echo "$unit: pull failed; not restarting" >&2
          elif [[ "$restart" == 1 ]]; then
            echo "$unit: new image(s) pulled; restarting"
            if [[ "$was_failed" == 1 ]]; then
              systemctl reset-failed "$unit.service" || true
            fi
            if systemctl restart "$unit.service"; then
              restarted+=("$unit")
            else
              echo "$unit: restart failed" >&2
              failed=1
            fi
          else
            echo "$unit: up to date"
          fi
        }

        ${lib.concatStringsSep "\n" (lib.mapAttrsToList (
            name: images: "update_service ${lib.escapeShellArgs ([name] ++ images)}"
          )
          serviceImages)}

        echo "Restarted with new images: ''${restarted[*]:-none}"
        exit "$failed"
      '';
    };

    systemd.timers.docker-compose-auto-update = {
      description = "Weekly docker-compose image auto-update";
      wantedBy = ["timers.target"];
      timerConfig = {
        OnCalendar = "Sun *-*-* 04:00:00";
        Persistent = true;
      };
    };
  };
}
