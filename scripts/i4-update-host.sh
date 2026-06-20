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
# Environment:
#   USE_BITWARDEN=1  Use the Bitwarden SSH agent socket instead of the default
#                    agent (e.g. Secretive). Requires the Bitwarden desktop app
#                    running with the SSH agent enabled.
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

# Optionally route all SSH connections through the Bitwarden agent socket. This
# overrides the IdentityAgent set in ~/.ssh/config (which points at Secretive).
sshAgentOpts=()
if [[ "${USE_BITWARDEN:-}" == "1" ]]; then
    bitwardenSocket="${HOME}/Library/Containers/com.bitwarden.desktop/Data/.bitwarden-ssh-agent.sock"
    if [[ ! -S "$bitwardenSocket" ]]; then
        echo "Error: USE_BITWARDEN=1 but Bitwarden SSH agent socket not found at ${bitwardenSocket}" >&2
        echo "Make sure the Bitwarden desktop app is running with the SSH agent enabled." >&2
        exit 1
    fi
    echo "Using Bitwarden SSH agent socket"
    sshAgentOpts=(-o "IdentityAgent=${bitwardenSocket}")
    export NIX_SSHOPTS="${NIX_SSHOPTS:-} -o IdentityAgent=${bitwardenSocket}"
fi

has_nixos_rebuild_arg() {
    local expectedArg="$1"

    for arg in "${nixosRebuildArgs[@]}"; do
        if [[ "$arg" == "$expectedArg" ]]; then
            return 0
        fi
    done

    return 1
}

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

remoteTarget="ilma4@${sshTarget}"
sudoPasswordArgs=()
if ssh "${sshAgentOpts[@]}" "${remoteTarget}" "sudo -n true" &>/dev/null; then
    echo "Remote sudo is available without password"
elif ! has_nixos_rebuild_arg "--ask-sudo-password"; then
    echo "Remote sudo requires a password; adding --ask-sudo-password"
    sudoPasswordArgs=("--ask-sudo-password")
fi

nix shell nixpkgs#nixos-rebuild-ng --command nixos-rebuild switch \
    --flake "${flakeRef}" \
    --target-host "${remoteTarget}" \
    --build-host "${remoteTarget}" \
    --sudo \
    "${sudoPasswordArgs[@]}" \
    "${nixosRebuildArgs[@]}"
