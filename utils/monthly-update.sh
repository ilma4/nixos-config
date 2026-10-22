#!/usr/bin/env bash
set -euo pipefail

# Check the launchd environment before any updater can write files.
for program in date cat mkdir mv jj nix bun git; do
  command -v "$program" >/dev/null || {
    echo "Required program is missing from PATH: $program" >&2
    exit 1
  }
done

# Find the latest last-Sunday-at-05:00 deadline, using GNU date. A missed
# month is coalesced into the latest due update, not replayed individually.
now=$(date +%s)
month=$(date -d "@$now" +%Y-%m)
last_day=$(date -d "$month-01 +1 month -1 day" +%F)
weekday=$(date -d "$last_day" +%w)
last_sunday=$(date -d "$last_day -$weekday days" +%F)
deadline=$(date -d "$last_sunday 05:00:00" +%s)
if (( now < deadline )); then
  month=$(date -d "$month-01 -1 month" +%Y-%m)
fi

state_dir="$HOME/.local/state/nixos-config-monthly-update"
state_file="$state_dir/last-successful-month"
last_success=""
if [[ -f "$state_file" ]]; then
  last_success=$(cat "$state_file")
  if [[ ! "$last_success" =~ ^[0-9]{4}-(0[1-9]|1[0-2])$ ]]; then
    echo "Invalid monthly update state: $state_file" >&2
    exit 1
  fi
fi
if [[ "$last_success" == "$month" || "$last_success" > "$month" ]]; then
  exit 0
fi
mkdir -p "$state_dir"

cd "$HOME/.config/nixos-config"

original_change=$(jj log -r @ --no-graph -T 'change_id')
original_empty=$(jj log -r @ --no-graph -T 'empty')

restore_original() {
  local rc=$?
  trap - EXIT
  if [[ "$original_empty" != true ]]; then
    if ! jj edit "$original_change"; then
      echo "Failed to restore original change $original_change" >&2
      exit 1
    fi
  fi
  # Only acknowledge success after every update and workspace restoration.
  # launchd serializes this agent; rename makes the persistent marker atomic.
  if (( rc == 0 )); then
    printf '%s\n' "$month" > "$state_file.tmp"
    mv -f "$state_file.tmp" "$state_file"
  fi
  exit "$rc"
}
trap restore_original EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

if [[ "$original_empty" != true ]]; then
  jj new @-
fi

nix flake update
jj commit -m "flake update" flake.lock
bun utils/update-immich.ts
bun utils/update-paperless.ts
