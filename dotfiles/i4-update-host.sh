#!/usr/bin/env bash
# i4-update-host: Switch a remote NixOS host to the specified flake configuration.
#
# Usage:
#   i4-update-host <flake-location>#<configuration> [targetHost] [nixos-rebuild-args...]
#
# Arguments:
#   <flake-location>#<configuration>  Flake reference (e.g., .#nas or /path/to/flake#nas)
#   [targetHost]                      Optional SSH target host (defaults to <configuration>)
#   [nixos-rebuild-args...]           Extra arguments forwarded to nixos-rebuild
#
# Notes:
# - Uses `nix shell nixpkgs#nixos-rebuild` so it works on macOS/Linux without nixos-rebuild pre-installed.
# - Connects to the remote host as `ilma4` and uses sudo for activation.
# - Tries <targetHost>.local first, falls back to <targetHost> if unreachable.

set -euo pipefail

if [[ ${1-} == "" ]]; then
    echo "Error: No flake reference provided."
    echo "Usage: i4-update-host <flake-location>#<configuration> [targetHost] [nixos-rebuild-args...]"
    exit 1
fi

flakeRef="$1"
shift

# Extract configuration name from flake reference (part after #)
if [[ "$flakeRef" != *"#"* ]]; then
    echo "Error: Flake reference must contain '#' (e.g., .#nas)"
    exit 1
fi

config="${flakeRef##*#}"
targetHost="$config"
if [[ ${1-} != "" && ${1-} != --* ]]; then
    targetHost="$1"
    shift
fi
nixosRebuildArgs=("$@")

host_responds_to_ping() {
    local host="$1"

    case "$(uname -s)" in
        Darwin)
            ping -c 1 -W 1000 "$host" &>/dev/null
            ;;
        Linux)
            ping -c 1 -W 1 "$host" &>/dev/null
            ;;
        *)
            ping -c 1 "$host" &>/dev/null
            ;;
    esac
}

# Check if targetHost.local is reachable (ping with 1 second timeout, 1 packet)
if host_responds_to_ping "${targetHost}.local"; then
    echo "Using ${targetHost}.local (mDNS)"
    sshTarget="${targetHost}.local"
else
    echo "Using ${targetHost}"
    sshTarget="${targetHost}"
fi

nix shell nixpkgs#nixos-rebuild-ng --command nixos-rebuild-ng switch \
    --flake "${flakeRef}" \
    --target-host "ilma4@${sshTarget}" \
    --build-host "ilma4@${sshTarget}" \
    --sudo \
    "${nixosRebuildArgs[@]}"
