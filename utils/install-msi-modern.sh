#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
default_flake_location="$(cd -- "${script_dir}/.." && pwd -P)"
flake_location="${FLAKE_LOCATION:-${default_flake_location}}"
target_disk="/dev/disk/by-path/pci-0000:01:00.0-nvme-1"

if ((EUID != 0)); then
    echo "Run this script as root; it will erase ${target_disk}." >&2
    exit 1
fi

if [[ ! -b "${target_disk}" ]]; then
    echo "Target disk does not exist or is not a block device: ${target_disk}" >&2
    exit 1
fi

# disko-install evaluates the installation configuration with --impure.
export I4_DISABLE_INITRD_SSH=1

exec nix run \
    --impure \
    --inputs-from "path:${flake_location}" \
    disko#disko-install \
    -- \
    --mode format \
    --write-efi-boot-entries \
    --flake "path:${flake_location}#msi-modern" \
    --disk main "${target_disk}"
