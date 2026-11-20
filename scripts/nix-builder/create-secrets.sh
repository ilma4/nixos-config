#!/usr/bin/env bash
set -euo pipefail

repo_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd -P)"
cd "$repo_dir"

secrets_file=secrets/example.yaml
secret_key=nas-msi-modern-builder-ssh-key
if grep -q "^$secret_key:" "$secrets_file"; then
    echo "Builder key already exists; refusing to replace it." >&2
    exit 1
fi

umask 077
tmp_dir="$(mktemp -d /dev/shm/nas-nix-builder.XXXXXXXX)"
trap 'rm -rf -- "$tmp_dir"' EXIT

ssh-keygen -q -t ed25519 -N '' -C nas-to-msi-modern-nix-builder -f "$tmp_dir/id_ed25519"
python3 -c 'import json,sys; print(json.dumps(sys.stdin.read()))' < "$tmp_dir/id_ed25519" \
    | ./scripts/sops/i4-sops-sudo set --value-stdin "$secrets_file" "[\"$secret_key\"]"
cat "$tmp_dir/id_ed25519.pub"
