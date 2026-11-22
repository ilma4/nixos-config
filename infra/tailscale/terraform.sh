#!/usr/bin/env bash
set -euo pipefail
set +x

usage() {
    echo "Usage: $0 validate|plan|deploy"
}

case "${1-}" in
    -h|--help) usage; exit 0 ;;
    validate|plan|deploy) action=$1 ;;
    *) usage >&2; exit 2 ;;
esac
[[ $# -eq 1 ]] || { usage >&2; exit 2; }

project_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
repo_dir="$(cd -- "$project_dir/../.." && pwd -P)"
cd "$project_dir"
umask 077

if ! command -v terraform >/dev/null 2>&1; then
    echo "Terraform not found. From the repo root, run: nix develop .#tailscale-terraform" >&2
    exit 1
fi

init=(terraform init -input=false -lockfile=readonly)
if [[ "$action" == validate ]]; then
    terraform fmt -check
    "${init[@]}" -backend=false
    exec terraform validate
fi

if [[ ! -s terraform.tfstate ]]; then
    echo "Existing terraform.tfstate not found. Restore the local state before running $action; see infra/tailscale/README.md." >&2
    exit 1
fi

secrets_file="$repo_dir/secrets/example.yaml"
sops="$repo_dir/scripts/sops/i4-sops-sudo"
if ! grep -q '^tailscale-terraform:' "$secrets_file"; then
    echo "Tailscale Terraform credentials are missing. From the repo root, run: ./scripts/tailscale-terraform/create-secrets.sh" >&2
    exit 1
fi

client_id="$("$sops" decrypt --extract '["tailscale-terraform"]["client_id"]' "$secrets_file")"
client_secret="$("$sops" decrypt --extract '["tailscale-terraform"]["client_secret"]' "$secrets_file")"
if [[ -z "$client_id" || -z "$client_secret" ]]; then
    echo "Tailscale Terraform credentials are incomplete. Rerun create-secrets.sh." >&2
    exit 1
fi

# Use the repository's OAuth credentials, not another Tailscale login in the shell.
unset TAILSCALE_API_KEY TAILSCALE_IDENTITY_TOKEN TAILSCALE_AUDIENCE
export TAILSCALE_OAUTH_CLIENT_ID="$client_id" TAILSCALE_OAUTH_CLIENT_SECRET="$client_secret"

"${init[@]}"
case "$action" in
    plan) exec terraform plan -input=false ;;
    deploy) exec terraform apply -input=true -auto-approve=false ;;
esac
