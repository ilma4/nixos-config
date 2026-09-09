#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
default_flake_location="$(cd -- "${script_dir}/.." && pwd -P)"
flake_location="${FLAKE_LOCATION:-${default_flake_location}}"

instance="android"
configuration="android-vm"
remote_config_dir="/etc/nixos"
remote_tmp=""

if [[ $# -ne 0 ]]; then
    echo "Usage: $0" >&2
    exit 2
fi

if ! command -v limactl-android >/dev/null 2>&1; then
    echo "Error: limactl-android is required." >&2
    exit 1
fi

if ! command -v rsync >/dev/null 2>&1; then
    echo "Error: rsync is required." >&2
    exit 1
fi

if [[ ! -d "${flake_location}" ]]; then
    echo "Error: flake directory does not exist: ${flake_location}" >&2
    exit 1
fi
flake_location="$(cd -- "${flake_location}" && pwd -P)"

if [[ ! -f "${flake_location}/flake.nix" ]]; then
    echo "Error: flake.nix not found in ${flake_location}." >&2
    exit 1
fi

cleanup() {
    if [[ -n "${remote_tmp}" ]]; then
        limactl-android shell -y "${instance}" -- rm -rf -- "${remote_tmp}" >/dev/null 2>&1 || true
    fi
}

remote_tmp_candidate="$(limactl-android shell -y "${instance}" -- mktemp -d /tmp/nixos-config.XXXXXX)"
if [[ "${remote_tmp_candidate}" != /tmp/nixos-config.* ]]; then
    echo "Error: guest returned an unexpected temporary directory: ${remote_tmp_candidate}" >&2
    exit 1
fi
remote_tmp="${remote_tmp_candidate}"
trap cleanup EXIT

echo "Syncing ${flake_location} to ${instance}:${remote_config_dir}"
limactl-android copy \
    --backend=rsync \
    --recursive \
    "${flake_location}" \
    "${instance}:${remote_tmp}"

limactl-android shell -y "${instance}" -- \
    sudo rsync --archive --delete "${remote_tmp}/" "${remote_config_dir}/"

echo "Switching ${instance} to ${configuration}"
limactl-android shell -y "${instance}" -- \
    sudo nixos-rebuild switch --flake "${remote_config_dir}#${configuration}"
