#!/usr/bin/env bash
set -euo pipefail

usage() {
    cat <<'EOF'
Usage: git resign [--rebase-merges|--no-rebase-merges] [base]

Re-signs your local (unpushed) commits with the configured Git signing key by
amending each one. "Local" means reachable from HEAD but on no remote-tracking
branch, so already-published commits are left untouched and no upstream needs
to be configured. Unlike 'git spush' it stops after signing and never pushes.

The rebase base is always an ancestor of HEAD, so resigning never rebases over
a remote: commits dropped from local history are not brought back, even when
they still exist on the remote.

With an explicit [base] (a commit or branch), signing starts at the merge base
of [base] and HEAD, which keeps the base an ancestor of HEAD as well.

Examples:
  git resign
  git resign HEAD~3
EOF
}

rebase_merges="auto"
base_arg=""

while (($# > 0)); do
    case "$1" in
        -h|--help)
            usage
            exit 0
            ;;
        --rebase-merges)
            rebase_merges="yes"
            shift
            ;;
        --no-rebase-merges)
            rebase_merges="no"
            shift
            ;;
        -*)
            echo "git resign: unknown option: $1" >&2
            usage >&2
            exit 2
            ;;
        *)
            base_arg="$1"
            shift
            ;;
    esac
done

if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    echo "git resign: not inside a Git work tree" >&2
    exit 1
fi

if ! git diff --quiet || ! git diff --cached --quiet; then
    echo "git resign: working tree has uncommitted changes; commit or stash them first" >&2
    exit 1
fi

# Resolve the commit to replay local commits onto. It is always an ancestor of
# HEAD, which is what guarantees resigning never reaches over the remote to
# resurrect commits that were dropped from local history. An empty base means
# "rebase from the root" (only when the repo has no remotes at all).
if [ -n "$base_arg" ]; then
    if ! git rev-parse --verify --quiet "$base_arg^{commit}" >/dev/null; then
        echo "git resign: base '$base_arg' does not exist" >&2
        exit 1
    fi
    # Clamp an explicit base to its merge base with HEAD so it can never sit
    # ahead of HEAD (e.g. a remote branch) and drag published commits back in.
    base=$(git merge-base "$base_arg" HEAD) || {
        echo "git resign: '$base_arg' has no common ancestor with HEAD" >&2
        exit 1
    }
else
    # Local (unpushed) commits: reachable from HEAD but on no remote-tracking
    # branch. Replay onto the parent of the oldest such commit.
    oldest_local=$(git rev-list --topo-order HEAD --not --remotes | tail -n1)
    if [ -z "$oldest_local" ]; then
        echo "git resign: no local (unpushed) commits to sign"
        exit 0
    fi
    base=$(git rev-parse --verify --quiet "${oldest_local}^" || true)
fi

if [ -n "$base" ]; then
    range="$base..HEAD"
    rebase_target=("$base")
else
    range="HEAD"
    rebase_target=(--root)
fi

if [ -z "$(git rev-list --max-count=1 "$range")" ]; then
    echo "git resign: no local (unpushed) commits to sign"
    exit 0
fi

rebase_args=()
if [ "$rebase_merges" = "yes" ]; then
    rebase_args+=(--rebase-merges)
elif [ "$rebase_merges" = "auto" ] && [ -n "$(git rev-list --min-parents=2 --max-count=1 "$range")" ]; then
    rebase_args+=(--rebase-merges)
fi

git rebase "${rebase_args[@]}" --exec 'git commit --amend --no-edit -S --allow-empty' "${rebase_target[@]}"
