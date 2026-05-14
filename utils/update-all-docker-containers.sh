#!/usr/bin/env bash
set -euo pipefail

script_dir=$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
repo_root=$(CDPATH='' cd -- "$script_dir/.." && pwd)

usage() {
    cat >&2 <<'EOF'
Usage: update-all-docker-containers.sh [--dry-run|--apply]

Runs the deterministic single-service updater for every simple docker-compose
service in this repository. Dry-run is the default; pass --apply to write
new version values into the Nix files.
EOF
}

mode=--dry-run

while [ "$#" -gt 0 ]; do
    case "$1" in
        --dry-run)
            mode=--dry-run
            shift
            ;;
        --apply)
            mode=--apply
            shift
            ;;
        -h | --help)
            usage
            exit 0
            ;;
        *)
            echo "Error: unknown option: $1" >&2
            usage
            exit 2
            ;;
    esac
done

cd "$repo_root"

if [ ! -x "$script_dir/update-docker-container" ]; then
    echo "Error: required updater is missing or not executable: $script_dir/update-docker-container" >&2
    exit 1
fi

services=(
    "hosts/nas/docker-services/actual-budget.nix|actualbudget/actual|actual-version||"
    "hosts/nas/docker-services/audiobookshelf.nix|advplyr/audiobookshelf|version|v|"
    "hosts/nas/docker-services/grafana.nix|grafana/grafana|version|v|docker-build-metadata"
    "hosts/nas/docker-services/home-assistant.nix|home-assistant/core|home-assistant-version||"
    "hosts/nas/docker-services/node-exporter.nix|prometheus/node_exporter|node-exporter-version||"
    "hosts/nas/docker-services/pdf-tools.nix|Stirling-Tools/Stirling-PDF|version|v|"
    "hosts/nas/docker-services/pihole.nix|pi-hole/docker-pi-hole|version||"
    "hosts/nas/docker-services/traefik.nix|traefik/traefik|version||"
    "hosts/nas/prometheus/prometheus.nix|prometheus/alertmanager|alertmanagerVersion||"
    "hosts/nas/prometheus/prometheus.nix|prometheus/prometheus|version||"
)

# qBittorrent is intentionally excluded: the Nix file uses hotio image tags,
# while qbittorrent/qBittorrent releases do not expose the current tag history
# needed for deterministic changelog ranges.

for service in "${services[@]}"; do
    IFS='|' read -r service_file github_repo version_name release_prefix metadata_mode <<<"$service"

    echo
    echo "==> $service_file ($github_repo)"

    args=("$mode" "--version-name" "$version_name")
    if [ -n "$release_prefix" ]; then
        args+=("--release-prefix" "$release_prefix")
    fi
    case "$metadata_mode" in
        "")
            ;;
        docker-build-metadata)
            args+=("--docker-build-metadata")
            ;;
        *)
            echo "Error: unknown metadata mode for $service_file: $metadata_mode" >&2
            exit 2
            ;;
    esac
    args+=("$service_file" "$github_repo")

    "$script_dir/update-docker-container" "${args[@]}"
done
