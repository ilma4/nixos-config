#!/usr/bin/env bash
set -euo pipefail

helper="$(dirname -- "${BASH_SOURCE[0]}")/../scripts/nix-rebuild.sh"
work="$(mktemp -d)"
trap 'rm -rf -- "$work"' EXIT
source_dir="$work/source checkout"
mkdir -p "$source_dir/nested/generated" "$source_dir/.jj" "$source_dir/tmp"
printf '{ outputs = { self }: { fixture = self.outPath; }; }\n' > "$source_dir/flake.nix"
printf 'old\n' > "$source_dir/edited"
touch "$source_dir/deleted" "$source_dir/ignored"
git init -q "$source_dir"
git -C "$source_dir" add --force --all
cp "$source_dir/.git/index" "$work/original-index"

printf 'new\n' > "$source_dir/edited"
rm "$source_dir/deleted"
printf '/tmp/\n/ignored\n' > "$source_dir/.gitignore"
printf '/generated/*\n!/generated/keep\n' > "$source_dir/nested/.gitignore"
touch "$source_dir/tmp/cache" "$source_dir/.jj/state" \
    "$source_dir/nested/generated/skip" "$source_dir/nested/generated/keep"
new_file=$'new file\nwith newline'
touch "$source_dir/$new_file"
chmod +x "$source_dir/$new_file"
ln -s edited "$source_dir/link"
git init -q "$source_dir/embedded"
touch "$source_dir/embedded/secret"

status=0
GIT_INDEX_FILE="$source_dir/.git/index" bash "$helper" "$source_dir" configured-host \
    bash -c '
        set -euo pipefail
        [[ $# == 4 && $3 == --flake && $4 == git+file:///*#configured-host ]]
        snapshot="${4#git+file://}"
        snapshot="${snapshot%#*}"
        printf "%s\n" "$snapshot" > "$1/snapshot"
        read -r mode _ < <(ls -ld "$(dirname -- "$snapshot")")
        [[ $mode == drwx------* ]]
        [[ $(cat "$snapshot/edited") == new ]]
        [[ -x "$snapshot/$2" && -L "$snapshot/link" ]]
        [[ -f "$snapshot/nested/generated/keep" ]]
        for omitted in deleted ignored tmp .jj embedded nested/generated/skip; do
            [[ ! -e "$snapshot/$omitted" ]]
        done

        # Verify the staged contents are visible to Nix, not just in the copy.
        [[ -z ${GIT_INDEX_FILE+x} ]]
        store_path=$(nix eval --offline --raw "${4%#*}#fixture")
        [[ -f "$store_path/$2" && ! -e "$store_path/.git" && ! -e "$store_path/ignored" ]]
        exit 42
    ' _ "$work" "$new_file" || status=$?
[[ $status == 42 ]]
[[ ! -e $(cat "$work/snapshot") ]]
cmp "$source_dir/.git/index" "$work/original-index"

# A plain directory (e.g. /etc/nixos in the Android VM) needs no source index.
rm -r "$source_dir/.git"
bash "$helper" "$source_dir" configured-host bash -c '
    set -euo pipefail
    [[ $2 == --flake ]]
    snapshot="${3#git+file://}"
    snapshot="${snapshot%#*}"
    printf "%s\n" "$snapshot" > "$1/snapshot"
    git -C "$snapshot" ls-files --error-unmatch flake.nix >/dev/null
' _ "$work"
[[ ! -e $(cat "$work/snapshot") ]]
[[ ! -e "$source_dir/.git" ]]
