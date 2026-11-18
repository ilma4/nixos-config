#!/usr/bin/env bash
set -euo pipefail

repo_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd -P)"
cd "$repo_dir"

if grep -q '^obsidian-livesync:' secrets/example.yaml; then
    echo "The LiveSync credential already exists." >&2
    exit 1
fi

python3 - <<'PY' | ./scripts/sops/i4-sops-sudo set --value-stdin secrets/example.yaml '["obsidian-livesync"]'
import hashlib
import json
import secrets

password = secrets.token_urlsafe(32)
salt = secrets.token_hex(16)
iterations = 600_000
digest = hashlib.pbkdf2_hmac("sha256", password.encode(), salt.encode(), iterations).hex()
verifier = f"-pbkdf2:sha256-{digest},{salt},{iterations}"
print(json.dumps({"password": password, "admin-ini": f"[admins]\nobsidian = {verifier}\n"}))
PY
./scripts/sops/i4-sops-sudo unset --idempotent secrets/example.yaml '["obsidian-webdav-htpasswd"]'
