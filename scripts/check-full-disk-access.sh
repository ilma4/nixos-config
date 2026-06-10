#!/usr/bin/env bash
# Check whether a macOS binary or .app bundle has Full Disk Access.

set -euo pipefail

usage() {
  echo "Usage: $0 <binary|path|app>" >&2
}

sql_quote() {
  printf "'%s'" "${1//\'/\'\'}"
}

abs_path() {
  local path="$1" dir base
  while [[ "$path" == */ && "$path" != / ]]; do
    path="${path%/}"
  done
  if [[ "$path" == /* ]]; then
    printf '%s\n' "$path"
    return
  fi

  dir="${path%/*}"
  base="${path##*/}"
  [[ "$dir" == "$path" ]] && dir=.
  (cd "$dir" && printf '%s/%s\n' "$PWD" "$base")
}

csreq_hex() {
  local target="$1" req tmp
  req="$(/usr/bin/codesign -dr - "$target" 2>&1 | /usr/bin/sed -n 's/.*designated => //p' || true)"
  [[ -n "$req" ]] || return 0

  tmp="$(/usr/bin/mktemp -t tcc-csreq.XXXXXX)"
  if /usr/bin/csreq -r "=$req" -b "$tmp" >/dev/null 2>&1; then
    /usr/bin/od -An -tx1 -v "$tmp" | /usr/bin/tr -d ' \n'
  fi
  /bin/rm -f "$tmp"
}

count_rows() {
  local db="$1" where="$2"
  "$sqlite" -noheader "$db" \
    "select count(*) from access where service = 'kTCCServiceSystemPolicyAllFiles' and ($where);" \
    2>/dev/null || echo 0
}

if [[ $# -ne 1 ]]; then
  usage
  exit 2
fi

if [[ "$(uname -s)" != Darwin ]]; then
  echo "Full Disk Access is a macOS-only permission." >&2
  exit 3
fi

sqlite="$(type -P sqlite3 || true)"
if [[ -z "$sqlite" ]]; then
  echo "Error: sqlite3 is required." >&2
  exit 2
fi

input="$1"
target="$input"
case "$target" in
  '~') target="$HOME" ;;
  '~/'*) target="$HOME/${target#~/}" ;;
esac

if [[ "$target" != */* && ! -e "$target" ]]; then
  target="$(type -P -- "$target" || true)"
  if [[ -z "$target" ]]; then
    echo "Error: binary not found in PATH: $input" >&2
    exit 2
  fi
fi

if [[ ! -e "$target" ]]; then
  echo "Error: path does not exist: $target" >&2
  exit 2
fi

path="$(abs_path "$target")"
resolved="$(realpath "$path")"
csreq="$(csreq_hex "$resolved")"

if [[ -f "$resolved/Contents/Info.plist" ]]; then
  is_app=1
  bundle_id="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$resolved/Contents/Info.plist" 2>/dev/null || true)"
  if [[ -z "$bundle_id" ]]; then
    echo "Error: app has no CFBundleIdentifier: $resolved" >&2
    exit 2
  fi
  label="app $bundle_id ($resolved)"
  client_where="client_type = 0 and client = $(sql_quote "$bundle_id")"
else
  is_app=0
  [[ -x "$resolved" ]] || echo "Warning: not executable: $resolved" >&2
  label="binary $path"
  client_where="client_type = 1 and (client = $(sql_quote "$path") or client = $(sql_quote "$resolved"))"
fi

csreq_ok=1
csreq_bad=0
if [[ -n "$csreq" ]]; then
  quoted_csreq="$(sql_quote "$csreq")"
  if ((is_app)); then
    csreq_ok="upper(hex(csreq)) = upper($quoted_csreq)"
    csreq_bad="(csreq is null or upper(hex(csreq)) != upper($quoted_csreq))"
  else
    csreq_ok="(csreq is null or upper(hex(csreq)) = upper($quoted_csreq))"
    csreq_bad="(csreq is not null and upper(hex(csreq)) != upper($quoted_csreq))"
  fi
elif ((is_app)); then
  csreq_ok=0
fi

found=0
allowed=0
stale=0
denied=0
readable=0
for db in \
  "/Library/Application Support/com.apple.TCC/TCC.db" \
  "$HOME/Library/Application Support/com.apple.TCC/TCC.db"; do
  [[ -r "$db" ]] || continue
  readable=1
  found=$((found + $(count_rows "$db" "$client_where")))
  allowed=$((allowed + $(count_rows "$db" "$client_where and auth_value = 2 and $csreq_ok")))
  stale=$((stale + $(count_rows "$db" "$client_where and auth_value = 2 and $csreq_bad")))
  denied=$((denied + $(count_rows "$db" "$client_where and auth_value = 0")))
done

if ((allowed > 0)); then
  echo "Full Disk Access is granted for $label"
  exit 0
fi

if ((readable == 0)); then
  echo "No readable TCC database found." >&2
elif ((stale > 0)); then
  echo "Full Disk Access grant exists for $label, but its code signature no longer matches."
elif ((denied > 0)); then
  echo "Full Disk Access is denied for $label."
elif ((found > 0)); then
  echo "Full Disk Access is not granted for $label."
else
  echo "No Full Disk Access entry found for $label."
fi
exit 1
