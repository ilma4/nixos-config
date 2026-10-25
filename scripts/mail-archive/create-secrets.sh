#!/usr/bin/env bash
set -euo pipefail

usage() {
    echo "Usage: $0 gmail|yandex|proton|dovecot"
    echo "Store one provider's login and app/bridge password, or three Dovecot ARGON2ID hashes."
    echo "This script does not authenticate, deploy, or enable synchronization."
}

case "${1-}" in
    gmail|yandex|proton|dovecot) account=$1 ;;
    -h|--help) usage; exit 0 ;;
    *) usage >&2; exit 2 ;;
esac
[[ $# -eq 1 ]] || { usage >&2; exit 2; }

repo_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd -P)"
cd "$repo_dir"
command -v python3 >/dev/null
command -v sops >/dev/null
sudo -v
umask 077

read_value() {
    local prompt=$1
    read -r -s -p "$prompt" secret_value </dev/tty
    printf '\n' >/dev/tty
    [[ -n "$secret_value" ]] || { echo "An empty value is not allowed." >&2; exit 1; }
}

store_value() {
    local key=$1
    # Keep secret values out of command arguments and temporary plaintext files.
    printf '%s' "$secret_value" \
        | python3 -c 'import json,sys; print(json.dumps(sys.stdin.read()))' \
        | ./scripts/sops/i4-sops-sudo set --value-stdin secrets/example.yaml "[\"$key\"]"
    unset secret_value
}

if [[ "$account" == dovecot ]]; then
    password_file=''
    for login in gmail yandex proton; do
        read_value "ARGON2ID hash for local login $login (from doveadm pw -s ARGON2ID): "
        [[ "$secret_value" == '{ARGON2ID}$argon2id$'* ]] || {
            echo "Expected a complete {ARGON2ID} hash." >&2
            exit 1
        }
        password_file+="$login:$secret_value"$'\n'
    done
    secret_value=$password_file
    unset password_file
    store_value mail-dovecot-users
else
    read_value "Login identifier for $account: "
    store_value "mail-$account-user"
    read_value "App password for $account (hydroxide bridge password for Proton): "
    store_value "mail-$account"
fi

echo "Encrypted secrets updated. Runtime sops declarations and account validation are still required."
