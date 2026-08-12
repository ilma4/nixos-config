#!/usr/bin/env bash
set -euo pipefail

find_executable() {
    local pid="$1"
    local field

    # The first text mapping reported by lsof is the process executable.
    while IFS= read -r field; do
        case "$field" in
            n*)
                printf '%s\n' "${field#n}"
                return 0
                ;;
        esac
    done < <(@lsof@ -a -p "$pid" -d txt -Fn 2>/dev/null)

    return 1
}

if ! lock=$(git rev-parse --git-path index.lock 2>/dev/null); then
    echo "git break-lock: not inside a Git repository" >&2
    exit 1
fi

# --git-path resolves the main worktree and each linked worktree to its own
# index.lock. An existing lock with no open file descriptor is stale.
holders=$(@lsof@ -t -- "$lock" 2>/dev/null || true)
if [[ -z "$holders" ]]; then
    rm -f -- "$lock"
    exit 0
fi

printf 'git break-lock: refusing to remove %s; held by:\n' "$lock" >&2
while IFS= read -r pid; do
    if ! executable=$(find_executable "$pid"); then
        executable="<unknown; process exited>"
    fi
    printf '  pid %s, executable %s\n' "$pid" "$executable" >&2
done <<<"$holders"

exit 1
