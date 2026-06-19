#!/usr/bin/env bash
set -euo pipefail

usage() {
    cat <<'EOF'
Usage: git resign [--rebase-merges|--no-rebase-merges] [upstream]

Re-signs all commits in upstream..HEAD with the configured Git signing key by
amending each one. Unlike 'git spush' it stops after signing and never pushes.

Examples:
  git resign
  git resign origin/main
EOF
}

rebase_merges="auto"
upstream="@{u}"

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
            upstream="$1"
            shift
            ;;
    esac
done

if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    echo "git resign: not inside a Git work tree" >&2
    exit 1
fi

if ! git rev-parse --verify --quiet "$upstream" >/dev/null; then
    echo "git resign: upstream '$upstream' does not exist" >&2
    echo "Pass an upstream explicitly, e.g. 'git resign origin/main'." >&2
    exit 1
fi

if ! git diff --quiet || ! git diff --cached --quiet; then
    echo "git resign: working tree has uncommitted changes; commit or stash them first" >&2
    exit 1
fi

if [ -z "$(git rev-list --max-count=1 "$upstream"..HEAD)" ]; then
    echo "git resign: no commits to sign relative to '$upstream'"
    exit 0
fi

rebase_args=()
if [ "$rebase_merges" = "yes" ]; then
    rebase_args+=(--rebase-merges)
elif [ "$rebase_merges" = "auto" ] && [ -n "$(git rev-list --min-parents=2 --max-count=1 "$upstream"..HEAD)" ]; then
    rebase_args+=(--rebase-merges)
fi

git rebase "${rebase_args[@]}" --exec 'git commit --amend --no-edit -S --allow-empty' "$upstream"
