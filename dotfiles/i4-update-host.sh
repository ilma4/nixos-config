#!/usr/bin/env bash
# i4-update-host: Switch a remote NixOS host to the specified flake configuration.
#
# Usage:
#   i4-update-host <targetHost>
#
# Env:
#   CONFIG         Nix flake output/host to apply (defaults to <targetHost>)
#   FLAKE_LOCATION Path/URL to flake (defaults to "$HOME/.config/nixos-config")
#
# Notes:
# - Uses `nix shell nixpkgs#nixos-rebuild` so it works on macOS/Linux without nixos-rebuild pre-installed.
# - Connects to the remote host as root via SSH.

set -euo pipefail

if [[ ${1-} == "" ]]; then
  echo "Error: No 'targetHost' provided."
  echo "Usage: i4-update-host <targetHost>"
  exit 1
fi

targetHost="$1"
config="${CONFIG:-$targetHost}"
FLAKE_LOCATION="${FLAKE_LOCATION:-$HOME/.config/nixos-config}"

nix shell nixpkgs#nixos-rebuild --command nixos-rebuild switch \
  --flake "${FLAKE_LOCATION}#${config}" \
  --target-host "root@${targetHost}" \
  --build-host "root@${targetHost}" \
  --fast
