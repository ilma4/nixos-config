#!/usr/bin/env bash
set -euo pipefail

usage() {
    cat <<'EOF'
Usage: git resign [--rebase-merges|--no-rebase-merges] [base]

Signs your local (unpushed) commits with the configured Git signing key by
amending each one. "Local" means reachable from HEAD but on no remote-tracking
branch, so already-published commits are left untouched and no upstream needs
to be configured. Unlike 'git spush' it stops after signing and never pushes.

Only commits that need it are rewritten: commits that already carry a
signature keep their SHAs, and signing starts at the oldest unsigned commit
(its descendants must be rewritten anyway once it is amended). When every
local commit is already signed the command is a no-op.

All rewriting happens on a temporary branch in a temporary worktree; your
checkout, index and uncommitted changes are never touched. Only after every
commit is signed successfully is the current branch pointed at the rewritten
history. On any failure the temporary state is discarded and the repository
is left exactly as it was. Each signing attempt is retried up to 3 times to
ride out transient signer failures.

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

# Derive range/rebase_target from $base. An empty base means "from the root".
update_range() {
    if [ -n "$base" ]; then
        range="$base..HEAD"
        rebase_target=("$base")
    else
        range="HEAD"
        rebase_target=(--root)
    fi
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

update_range

if [ -z "$(git rev-list --max-count=1 "$range")" ]; then
    echo "git resign: no local (unpushed) commits to sign"
    exit 0
fi

# Signature status per commit: N = unsigned, B = bad signature; any other
# status means a usable signature is already present and the commit is left
# as it is. git log lists children before parents (--topo-order), so the last
# N/B line is the oldest commit that needs signing.
sig_scan=$(git log --topo-order --format='%H %G?' "$range" 2>/dev/null) || {
    echo "git resign: failed to read signature status for $range" >&2
    exit 1
}
oldest_unsigned=$(awk '$2 == "N" || $2 == "B" { c = $1 } END { if (c != "") print c }' <<<"$sig_scan")

if [ -z "$oldest_unsigned" ]; then
    echo "git resign: all local (unpushed) commits are already signed"
    exit 0
fi

total=$(git rev-list --count "$range")

# Advance the base past the already-signed prefix so those commits keep their
# SHAs. Only safe when the new base still contains the old one: the replayed
# range may shrink but never grow (growing could reach published commits).
if parent=$(git rev-parse --verify --quiet "${oldest_unsigned}^"); then
    if [ -z "$base" ] || git merge-base --is-ancestor "$base" "$parent"; then
        base="$parent"
        update_range
    fi
fi

to_sign=$(git rev-list --count "$range")
skipped=$((total - to_sign))

rebase_args=()
if [ "$rebase_merges" = "yes" ]; then
    rebase_args+=(--rebase-merges)
elif [ "$rebase_merges" = "auto" ] && [ -n "$(git rev-list --min-parents=2 --max-count=1 "$range")" ]; then
    rebase_args+=(--rebase-merges)
fi

orig_head=$(git rev-parse HEAD)
orig_branch=$(git symbolic-ref --quiet --short HEAD || true)

# All rewriting happens on a temporary branch in a temporary worktree, so the
# real checkout is never touched and any failure simply discards the copy.
tmp_branch="git-resign-tmp-$$-$(date +%s)"
tmpdir=""
wt=""

cleanup() {
    if [ -n "$wt" ] && [ -d "$wt" ]; then
        git -C "$wt" rebase --abort >/dev/null 2>&1 || true
        git worktree remove --force "$wt" >/dev/null 2>&1 || true
    fi
    if [ -n "$tmpdir" ]; then
        rm -rf "$tmpdir"
        git worktree prune >/dev/null 2>&1 || true
    fi
    git branch -D "$tmp_branch" >/dev/null 2>&1 || true
}
trap cleanup EXIT

fail() {
    echo "git resign: $1; the repository was left unchanged" >&2
    exit 1
}

tmpdir=$(mktemp -d "${TMPDIR:-/tmp}/git-resign.XXXXXX")
wt="$tmpdir/worktree"

if ! git worktree add --quiet -b "$tmp_branch" "$wt" HEAD; then
    fail "could not create a temporary worktree"
fi

# Each signing attempt is retried up to 3 times to ride out transient signer
# failures (an agent prompt timing out and the like). Expanded by the rebase
# exec shell, not here.
# shellcheck disable=SC2016
resign_cmd='try=0; until git commit --amend --no-edit -S --allow-empty; do try=$((try+1)); [ "$try" -le 3 ] || { echo "git resign: signing failed after 3 retries" >&2; exit 1; }; echo "git resign: signing failed; retrying ($try/3)" >&2; sleep 1; done'

if ! git -C "$wt" rebase "${rebase_args[@]}" --exec "$resign_cmd" "${rebase_target[@]}"; then
    fail "signing failed"
fi

new_head=$(git -C "$wt" rev-parse HEAD)

# Amending must only ever change signatures/committer data, never content.
if [ "$(git rev-parse "$orig_head^{tree}")" != "$(git rev-parse "$new_head^{tree}")" ]; then
    fail "rewritten history has a different tree than the original (this is a bug)"
fi

# Atomically point the branch (or detached HEAD) at the signed history; the
# old-value check refuses to clobber commits made while resigning was running.
# The trees are identical, so the checkout and index are unaffected.
if [ -n "$orig_branch" ]; then
    if ! git update-ref -m "git resign: sign $to_sign commit(s)" "refs/heads/$orig_branch" "$new_head" "$orig_head"; then
        fail "branch '$orig_branch' moved while resigning"
    fi
else
    if ! git update-ref --no-deref -m "git resign: sign $to_sign commit(s)" HEAD "$new_head" "$orig_head"; then
        fail "HEAD moved while resigning"
    fi
fi

if [ "$skipped" -gt 0 ]; then
    echo "git resign: left $skipped already-signed commit(s) untouched"
fi
echo "git resign: signed $to_sign commit(s) ($(git rev-parse --short "$orig_head") -> $(git rev-parse --short "$new_head"))"
