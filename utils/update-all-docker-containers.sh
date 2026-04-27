#!/usr/bin/env bash
set -euo pipefail

script_dir=$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
repo_root=$(CDPATH='' cd -- "$script_dir/.." && pwd)

cd "$repo_root"

if [ ! -x ./scripts/simple-service-update ]; then
    echo "Error: required updater is missing or not executable: ./scripts/simple-service-update" >&2
    exit 1
fi

services=(
    "hosts/nas/docker-services/actual-budget.nix|actualbudget/actual"
    "hosts/nas/docker-services/audiobookshelf.nix|advplyr/audiobookshelf"
    "hosts/nas/docker-services/grafana.nix|grafana/grafana"
    "hosts/nas/docker-services/home-assistant.nix|home-assistant/core"
    "hosts/nas/docker-services/node-exporter.nix|prometheus/node_exporter"
    "hosts/nas/docker-services/pdf-tools.nix|Stirling-Tools/Stirling-PDF"
    "hosts/nas/docker-services/pihole.nix|pi-hole/docker-pi-hole"
    "hosts/nas/docker-services/qbittorrent.nix|qbittorrent/qBittorrent"
    "hosts/nas/docker-services/traefik.nix|traefik/traefik"
    "hosts/nas/prometheus/prometheus.nix|prometheus/alertmanager"
    "hosts/nas/prometheus/prometheus.nix|prometheus/prometheus"
)

for service in "${services[@]}"; do
    service_file=${service%%|*}
    github_repo=${service#*|}

    echo "Updating $service_file from $github_repo"
    ./scripts/simple-service-update "$service_file" "$github_repo"
done
