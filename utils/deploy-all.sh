#!/usr/bin/env bash
set -euo pipefail

jobs=(nix-rebuild nas msi-modern)

cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.."

run_job() {
    local job="$1"
    local max_attempts=3
    local status=0
    local target="$job"
    local attempt

    if [[ "$job" != nix-rebuild ]] &&
        ssh -o BatchMode=yes -o ConnectTimeout=3 "ilma4@$job.local" true >/dev/null 2>&1; then
        target="$job.local"
    fi

    for ((attempt = 1; attempt <= max_attempts; attempt++)); do
        status=0
        echo "Deploying $job (attempt $attempt/$max_attempts)"

        if [[ "$job" == nix-rebuild ]]; then
            nix-rebuild || status=$?
        else
            echo "Updating $job via $target"
            ssh -o BatchMode=yes "ilma4@$target" \
                'sudo -n /run/current-system/sw/bin/update-to-latest.sh' || status=$?
        fi

        if ((status == 0)); then
            break
        fi

        if ((attempt < max_attempts)); then
            echo "Deployment of $job failed with status $status; retrying." >&2
        fi
    done

    printf '%s\n' "$status" >"$DEPLOY_STATUS_DIR/$job"
    return "$status"
}

if [[ "${1:-}" == --run-job ]]; then
    run_job "$2"
    exit
fi

if [[ -n "$(git status --porcelain)" ]]; then
    echo "Repository has uncommitted or untracked changes:" >&2
    git status --short >&2
    exit 1
fi

git spush
sudo -v

# mprocs does not propagate process failures, so each job records its status.
DEPLOY_STATUS_DIR="$(mktemp -d)"
export DEPLOY_STATUS_DIR
trap 'rm -rf -- "$DEPLOY_STATUS_DIR"' EXIT

commands=()
for job in "${jobs[@]}"; do
    commands+=("utils/deploy-all.sh --run-job $job")
done

mprocs \
    --names "$(IFS=,; printf '%s' "${jobs[*]}")" \
    --on-all-finished '{c: quit}' \
    "${commands[@]}"

failed=0
for job in "${jobs[@]}"; do
    status="not finished"
    [[ -f "$DEPLOY_STATUS_DIR/$job" ]] && status="$(<"$DEPLOY_STATUS_DIR/$job")"
    if [[ "$status" != 0 ]]; then
        echo "Failed $job ($status)" >&2
        failed=1
    fi
done

((failed == 0)) || exit 1
echo "Deploy completed successfully."
