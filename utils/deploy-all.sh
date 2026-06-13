#!/usr/bin/env bash
set -euo pipefail

# Remote hosts that enable modules/deploy.nix and provide update-to-latest.sh.
deploy_hosts=(
    nas
    msi-modern
)

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
repo_dir="$(cd -- "${script_dir}/.." && pwd -P)"

assert_repo_clear() {
    local status

    status="$(git status --porcelain=v1 --untracked-files=all)"
    if [[ -n "${status}" ]]; then
        echo "Repository has uncommitted or untracked changes:" >&2
        git status --short >&2
        exit 1
    fi
}

prime_local_sudo() {
    if command -v sudo >/dev/null 2>&1; then
        sudo -v
    fi
}

update_host_to_latest() {
    local host="$1"
    local ssh_target="${host}"

    if ssh -o BatchMode=yes -o ConnectTimeout=3 "ilma4@${host}.local" true >/dev/null 2>&1; then
        ssh_target="${host}.local"
    fi

    echo "Updating ${host} via ${ssh_target}"
    ssh -o BatchMode=yes "ilma4@${ssh_target}" \
        "sudo -n /run/current-system/sw/bin/update-to-latest.sh"
}

job_pids=()
job_names=()

start_job() {
    local name="$1"
    shift

    echo "Starting ${name}"
    "$@" &
    job_pids+=("$!")
    job_names+=("${name}")
}

stop_jobs() {
    local pid

    for pid in "${job_pids[@]}"; do
        kill "${pid}" 2>/dev/null || true
    done
}

trap stop_jobs INT TERM

cd "${repo_dir}"

assert_repo_clear

git spush

prime_local_sudo

start_job "nix-rebuild" nix-rebuild
for host in "${deploy_hosts[@]}"; do
    start_job "update-to-latest:${host}" update_host_to_latest "${host}"
done

failed=0
for index in "${!job_pids[@]}"; do
    if wait "${job_pids[${index}]}"; then
        echo "Finished ${job_names[${index}]}"
    else
        status="$?"
        echo "Failed ${job_names[${index}]} with exit code ${status}" >&2
        failed=1
    fi
done

if [[ "${failed}" -ne 0 ]]; then
    exit 1
fi

echo "Deploy completed successfully."
