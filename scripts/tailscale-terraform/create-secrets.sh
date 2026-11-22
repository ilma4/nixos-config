#!/usr/bin/env bash
set -euo pipefail
set +x

if [[ $# -ne 0 ]]; then
    echo "Usage: $0" >&2
    exit 2
fi

repo_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd -P)"
cd "$repo_dir"
umask 077

secrets_file=secrets/example.yaml
sops=./scripts/sops/i4-sops-sudo

# Check the identity and sudo access before asking for OAuth credentials.
if ! "$sops" decrypt "$secrets_file" >/dev/null; then
    echo "Restore an age identity authorized for $secrets_file, or set SOPS_AGE_KEY_FILE to its path. Then rerun this script." >&2
    exit 1
fi

read_credential() {
    read -r -s -p "$1" "$2" </dev/tty
    printf '\n' >/dev/tty
    if [[ -z "${!2}" ]]; then
        echo "Credential cannot be empty." >&2
        exit 1
    fi
}

read_credential "Tailscale Terraform OAuth client ID: " client_id
read_credential "Tailscale Terraform OAuth client secret: " client_secret

# Pass both fields via stdin and update them together. Do not write plaintext to disk.
printf '%s\n%s\n' "$client_id" "$client_secret" \
    | python3 -c 'import json, sys; client_id, client_secret = sys.stdin.read().splitlines(); print(json.dumps({"client_id": client_id, "client_secret": client_secret}))' \
    | "$sops" set --value-stdin "$secrets_file" '["tailscale-terraform"]'

echo "Saved Tailscale Terraform OAuth credentials in secrets/example.yaml."
