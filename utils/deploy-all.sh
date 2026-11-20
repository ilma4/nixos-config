#!/usr/bin/env bash
set -euo pipefail

jobs=(nix-rebuild nas)

cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.."

run_job() {
    local job="$1"
    local max_attempts=3
    local status=0
    local target="$job"
    local attempt

    case "$job" in
        nix-rebuild|nas) ;;
        *) echo "Unknown deployment job: $job" >&2; return 2 ;;
    esac

    if [[ "$job" == nas ]] &&
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
            echo "Deployment of $job failed with status $status; retrying in 1 second." >&2
            sleep 1
        fi
    done

    return "$status"
}

changes=$(jj diff --summary --color never)
if [[ -n "$changes" ]]; then
    echo "Repository has uncommitted or untracked changes:" >&2
    printf '%s\n' "$changes" >&2
    exit 1
fi

jj git fetch --remote origin --branch main

remote_changes=$(jj log --no-graph --color never -r '@-..main@origin' \
    -T 'commit_id.short() ++ " " ++ description.first_line() ++ "\n"')
if [[ -n "$remote_changes" ]]; then
    printf 'origin/main has commits not in the deployment target (@-):\n%s\n' "$remote_changes" >&2
    printf 'Rebase local changes onto origin/main first? [Y/n] ' >&2
    if ! read -r answer || [[ ! "$answer" =~ ^([yY]([eE][sS])?)?$ ]]; then
        echo 'Deployment cancelled; nothing was pushed.' >&2
        exit 1
    fi

    jj rebase -r 'main@origin..@' --onto main@origin
    conflicts=$(jj log --no-graph -r 'conflicts() & (main@origin..@)' -T 'commit_id')
    if [[ -n "$conflicts" ]]; then
        echo 'Rebase left conflicts. Resolve them before running deployment again.' >&2
        exit 1
    fi

    remote_changes=$(jj log --no-graph -r '@-..main@origin' -T 'commit_id')
    if [[ -n "$remote_changes" ]]; then
        echo 'Deployment target still does not contain origin/main; nothing was pushed.' >&2
        exit 1
    fi
fi

jj bookmark move main --to @-
jj git push --remote origin --bookmark main

# Run in the caller's terminal so nix-rebuild can prompt for credentials.
# Run one job at a time to avoid competing requests to the SSH agent.
deploy_status=0
for job in "${jobs[@]}"; do
    if run_job "$job"; then
        continue
    else
        status=$?
        echo "Deployment of $job failed with status $status." >&2
        deploy_status=$status
    fi
done

if ((deploy_status != 0)); then
    exit "$deploy_status"
fi

echo "Deploy finished."
