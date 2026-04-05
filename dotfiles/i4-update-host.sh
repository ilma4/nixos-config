#!/usr/bin/env bash
# i4-update-host: Switch a remote NixOS host to the specified flake configuration.
#
# Usage:
#   i4-update-host <flake-location>#<configuration> [targetHost]
#
# Arguments:
#   <flake-location>#<configuration>  Flake reference (e.g., .#nas or /path/to/flake#nas)
#   [targetHost]                      Optional SSH target host (defaults to <configuration>)
#
# Notes:
# - Uses `nix shell nixpkgs#nixos-rebuild` so it works on macOS/Linux without nixos-rebuild pre-installed.
# - Connects to the remote host as `ilma4` and uses sudo for activation.
# - Tries <targetHost>.local first, falls back to <targetHost> if unreachable.

set -euo pipefail

if [[ ${1-} == "" ]]; then
    echo "Error: No flake reference provided."
    echo "Usage: i4-update-host <flake-location>#<configuration> [targetHost]"
    exit 1
fi

flakeRef="$1"

# Extract configuration name from flake reference (part after #)
if [[ "$flakeRef" != *"#"* ]]; then
    echo "Error: Flake reference must contain '#' (e.g., .#nas)"
    exit 1
fi

config="${flakeRef##*#}"
targetHost="${2:-$config}"

# Check if targetHost.local is reachable (ping with 1 second timeout, 1 packet)
if ping -c 1 -W 1 "${targetHost}.local" &>/dev/null; then
    echo "Using ${targetHost}.local (mDNS)"
    sshTarget="${targetHost}.local"
else
    echo "Using ${targetHost}"
    sshTarget="${targetHost}"
fi

nix shell nixpkgs#nixos-rebuild --command nixos-rebuild switch \
    --flake "${flakeRef}" \
    --target-host "ilma4@${sshTarget}" \
    --build-host "ilma4@${sshTarget}" \
    --sudo \
    --fast
