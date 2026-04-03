#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SECRETS_FILE="${ROOT_DIR}/secrets/example.yaml"
SOPS_SUDO="${ROOT_DIR}/scripts/sops/i4-sops-sudo"

json_string() {
  local value="$1"

  value=${value//\\/\\\\}
  value=${value//\"/\\\"}
  value=${value//$'\n'/\\n}

  printf '"%s"' "$value"
}

if [[ ! -x "${SOPS_SUDO}" ]]; then
  echo "Missing helper script: ${SOPS_SUDO}" >&2
  exit 1
fi

if [[ ! -f "${SECRETS_FILE}" ]]; then
  echo "Missing secrets file: ${SECRETS_FILE}" >&2
  exit 1
fi

read -r -p "Telegram my_id: " telegram_my_id
read -r -s -p "Mallard bot token: " mallard_api_key
printf "\n"

if [[ -z "${telegram_my_id}" ]]; then
  echo "Telegram my_id cannot be empty." >&2
  exit 1
fi

if [[ -z "${mallard_api_key}" ]]; then
  echo "Mallard bot token cannot be empty." >&2
  exit 1
fi

json_string "${telegram_my_id}" | "${SOPS_SUDO}" --in-place set --input-type yaml --output-type yaml --value-stdin --idempotent "${SECRETS_FILE}" '["telegram"]["my_id"]'
json_string "${mallard_api_key}" | "${SOPS_SUDO}" --in-place set --input-type yaml --output-type yaml --value-stdin --idempotent "${SECRETS_FILE}" '["telegram"]["mallard"]["api_key"]'

echo "Updated ${SECRETS_FILE}"
