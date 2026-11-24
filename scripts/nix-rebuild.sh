#!/usr/bin/env bash
set -euo pipefail

source_dir="$(CDPATH= cd -- "${1:?Missing flake source directory}" && pwd -P)"
flake_output="${2:?Missing flake output name}"
shift 2

# Never reuse the caller's index or object database, even from a Git hook.
for name in $(git rev-parse --local-env-vars); do
    unset "$name"
done

# The private parent stays mode 0700 even if rsync preserves source permissions.
temp_dir="$(mktemp -d /tmp/nix-rebuild.XXXXXXXXXX)"
trap 'rm -rf -- "$temp_dir"' EXIT
trap 'exit 129' HUP
trap 'exit 130' INT
trap 'exit 143' TERM
snapshot="$temp_dir/source"

(
    export GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL=/dev/null
    git init --quiet --template= "$snapshot"

    # Use an empty index to apply Git's .gitignore rules to every file, even
    # previously tracked files. This also works for sources without .git.
    # Git lists embedded repositories as directory entries; skip those rather
    # than copying unfiltered contents or staging them as submodules.
    git --git-dir="$snapshot/.git" --work-tree="$source_dir" ls-files \
        --others --exclude-per-directory=.gitignore --exclude='/.jj' -z |
        while IFS= read -r -d '' file; do
            if [[ "$file" != */ ]]; then
                printf '%s\0' "$file"
            fi
        done |
        rsync -lp --chmod=Du+rwx --from0 --files-from=- -- "$source_dir/" "$snapshot/"

    # Nix reads the worktree but only includes files present in this index.
    git -C "$snapshot" add --force --all
)

"$@" --flake "git+file://$snapshot#$flake_output"
