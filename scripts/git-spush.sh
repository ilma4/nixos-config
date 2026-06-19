#!/usr/bin/env bash
set -euo pipefail

usage() {
    cat <<'EOF'
Usage: git spush [--rebase-merges|--no-rebase-merges] [upstream] [-- push-args...]

Signs all commits in upstream..HEAD with the configured Git signing key
(via 'git resign'), then runs git push.

Examples:
  git spush
  git spush origin/main
  git spush origin/main -- --set-upstream origin my-branch
EOF
}

# Args destined for git-resign (rebase-merges flags + optional upstream),
# collected in encountered order; git-resign accepts them in any order.
resign_args=()
push_args=()

while (($# > 0)); do
    case "$1" in
        -h|--help)
            usage
            exit 0
            ;;
        --rebase-merges|--no-rebase-merges)
            resign_args+=("$1")
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
            resign_args+=("$1")
            shift
            ;;
    esac
done

# Sign every commit in upstream..HEAD. The signing logic and all its
# preconditions (inside a work tree, upstream exists, clean tree, no-op when
# there is nothing unpublished) live in git-resign, which is reused here. The
# placeholder on the next line is replaced with git-resign's store path at
# build time (see home/base.nix), so git spush always invokes the matching
# git-resign regardless of $PATH.
@gitResign@ "${resign_args[@]}"

git push "${push_args[@]}"
