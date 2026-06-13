#!/usr/bin/env bash
set -euo pipefail

usage() {
    cat <<'EOF'
Usage: git spush [--rebase-merges|--no-rebase-merges] [upstream] [-- push-args...]

Signs all commits in upstream..HEAD with the configured Git signing key,
shows their signature status, then runs git push.

Examples:
  git spush
  git spush origin/main
  git spush origin/main -- --set-upstream origin my-branch
EOF
}

rebase_merges="auto"
upstream="@{u}"
push_args=()

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
        --)
            shift
            push_args=("$@")
            break
            ;;
        -*)
            echo "git spush: unknown option: $1" >&2
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
    echo "git spush: not inside a Git work tree" >&2
    exit 1
fi

if ! git rev-parse --verify --quiet "$upstream" >/dev/null; then
    echo "git spush: upstream '$upstream' does not exist" >&2
    echo "Pass an upstream explicitly, e.g. 'git spush origin/main'." >&2
    exit 1
fi

if ! git diff --quiet || ! git diff --cached --quiet; then
    echo "git spush: working tree has uncommitted changes; commit or stash them first" >&2
    exit 1
fi

if [ -z "$(git rev-list --max-count=1 "$upstream"..HEAD)" ]; then
    echo "git spush: no unpublished commits relative to '$upstream'"
    exec git push "${push_args[@]}"
fi

rebase_args=()
if [ "$rebase_merges" = "yes" ]; then
    rebase_args+=(--rebase-merges)
elif [ "$rebase_merges" = "auto" ] && [ -n "$(git rev-list --min-parents=2 --max-count=1 "$upstream"..HEAD)" ]; then
    rebase_args+=(--rebase-merges)
fi

git rebase "${rebase_args[@]}" --exec 'git commit --amend --no-edit -S --allow-empty' "$upstream"

# git log --show-signature --oneline "$upstream"..HEAD

git push "${push_args[@]}"
