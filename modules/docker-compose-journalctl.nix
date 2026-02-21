{
  lib,
  pkgs,
  config,
  ...
}: let
  enabledComposeServices = lib.filterAttrs (_: svc: svc.enable) config.dockerCompose;
  journalctlWithoutCompose = pkgs.writeShellScriptBin "i4-journalctl-no-compose" ''
    set -euo pipefail

    usage() {
      cat <<'EOF'
Usage: i4-journalctl-no-compose [journalctl args]

Show journald logs while excluding docker-compose services from this host.
Defaults to: -f -n 200

Examples:
  i4-journalctl-no-compose
  i4-journalctl-no-compose --since "1 hour ago"
  i4-journalctl-no-compose -b -p warning
EOF
    }

    if [[ "''${1:-}" == "-h" || "''${1:-}" == "--help" ]]; then
      usage
      exit 0
    fi

    declare -a journalctl_args
    if [[ "$#" -eq 0 ]]; then
      journalctl_args=(-f -n 200)
    else
      journalctl_args=("$@")
    fi

    readonly -a compose_units=(${lib.concatMapStringsSep " " (name: ''"${name}.service"'') (lib.attrNames enabledComposeServices)})

    if [[ "''${#compose_units[@]}" -eq 0 ]]; then
      exec env SYSTEMD_COLORS=1 ${pkgs.systemd}/bin/journalctl --no-pager "''${journalctl_args[@]}"
    fi

    declare -a exclude_matches=()
    for unit in "''${compose_units[@]}"; do
      exclude_matches+=("_SYSTEMD_UNIT!=''${unit}")
    done

    if env SYSTEMD_COLORS=1 ${pkgs.systemd}/bin/journalctl --no-pager -n 1 "''${exclude_matches[0]}" >/dev/null 2>&1; then
      exec env SYSTEMD_COLORS=1 ${pkgs.systemd}/bin/journalctl --no-pager "''${exclude_matches[@]}" "''${journalctl_args[@]}"
    fi

    regex=""
    for unit in "''${compose_units[@]}"; do
      escaped="$(${pkgs.gnused}/bin/sed 's/[][(){}.^$*+?|\\/]/\\&/g' <<< "''${unit}")"
      if [[ -z "''${regex}" ]]; then
        regex="''${escaped}"
      else
        regex="''${regex}|''${escaped}"
      fi
    done

    env SYSTEMD_COLORS=1 ${pkgs.systemd}/bin/journalctl --no-pager "''${journalctl_args[@]}" \
      | ${pkgs.gawk}/bin/awk -v re="''${regex}" '$0 !~ re { print; fflush(); }'
  '';
in {
  config = lib.mkIf config.i4.dockerComposeEnable {
    environment.systemPackages = [
      journalctlWithoutCompose
    ];
  };
}
