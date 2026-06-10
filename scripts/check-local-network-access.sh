#!/usr/bin/env bash
# Check whether a macOS binary or .app bundle has Local Network access.

set -euo pipefail

usage() {
  echo "Usage: $0 <binary|path|app>" >&2
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

plist_value() {
  local plist="$1" key="$2"
  /usr/libexec/PlistBuddy -c "Print :$key" "$plist" 2>/dev/null || true
}

codesign_identifier() {
  /usr/bin/codesign -dv "$1" 2>&1 | /usr/bin/sed -n 's/^Identifier=//p' | /usr/bin/head -n 1
}

if [[ $# -ne 1 ]]; then
  usage
  exit 2
fi

if [[ "$(uname -s)" != Darwin ]]; then
  echo "Local Network access is a macOS-only permission." >&2
  exit 3
fi

python3=/usr/bin/python3
if [[ ! -x "$python3" ]]; then
  python3="$(type -P python3 || true)"
fi
if [[ -z "$python3" ]]; then
  echo "Error: python3 is required." >&2
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

if [[ -f "$resolved/Contents/Info.plist" ]]; then
  bundle_id="$(plist_value "$resolved/Contents/Info.plist" CFBundleIdentifier)"
  if [[ -z "$bundle_id" ]]; then
    echo "Error: app has no CFBundleIdentifier: $resolved" >&2
    exit 2
  fi

  executable_name="$(plist_value "$resolved/Contents/Info.plist" CFBundleExecutable)"
  if [[ -z "$executable_name" ]]; then
    echo "Error: app has no CFBundleExecutable: $resolved" >&2
    exit 2
  fi

  executable_path="$resolved/Contents/MacOS/$executable_name"
  if [[ ! -e "$executable_path" ]]; then
    echo "Error: app executable does not exist: $executable_path" >&2
    exit 2
  fi

  input_executable_path="$path/Contents/MacOS/$executable_name"
  executable_resolved="$(realpath "$executable_path")"
  expected_identifier="$bundle_id"
  label="app $bundle_id ($resolved)"
  path_candidates=("$path" "$resolved" "$input_executable_path" "$executable_path" "$executable_resolved")
else
  [[ -x "$resolved" ]] || echo "Warning: not executable: $resolved" >&2
  expected_identifier="$(codesign_identifier "$resolved" || true)"
  if [[ -z "$expected_identifier" ]]; then
    echo "Warning: could not determine code signing identifier for $resolved; matching by path only." >&2
    label="binary $path"
  else
    label="binary $expected_identifier ($path)"
  fi
  path_candidates=("$path" "$resolved")
fi

exec "$python3" - "$expected_identifier" "$label" "${path_candidates[@]}" <<'PY'
import plistlib
import sys
from pathlib import Path

expected_identifier = sys.argv[1] or None
label = sys.argv[2]
path_candidates = set(sys.argv[3:])
plist_path = Path("/Library/Preferences/com.apple.networkextension.plist")

if not plist_path.exists():
    print(f"No Local Network preferences found for {label}.")
    sys.exit(1)

try:
    plist = plistlib.loads(plist_path.read_bytes())
except Exception as err:
    print(f"Could not read Local Network preferences at {plist_path}: {err}", file=sys.stderr)
    sys.exit(1)

objects = plist.get("$objects") if isinstance(plist, dict) else None
if not isinstance(objects, list):
    objects = []


def resolve(value):
    seen = set()
    while isinstance(value, plistlib.UID):
        index = value.data
        if index in seen or index < 0 or index >= len(objects):
            return None
        seen.add(index)
        value = objects[index]
    return value


def text(value):
    value = resolve(value)
    if value == "$null":
        return None
    if isinstance(value, bytes):
        try:
            return value.decode()
        except UnicodeDecodeError:
            return None
    if isinstance(value, str):
        return value
    return None


def truth(value):
    value = resolve(value)
    if value == "$null":
        return None
    if value is True:
        return True
    if value is False:
        return False
    return None


def walk(value):
    value = resolve(value)
    if isinstance(value, dict):
        yield value
        for nested in value.values():
            yield from walk(nested)
    elif isinstance(value, list):
        for nested in value:
            yield from walk(nested)


candidates = objects if objects else list(walk(plist))
entries = []
for item in candidates:
    if not isinstance(item, dict):
        continue

    signing_identifier = text(item.get("SigningIdentifier"))
    executable_path = text(item.get("Path"))
    if signing_identifier is None and executable_path is None:
        continue

    entries.append(
        {
            "signing_identifier": signing_identifier,
            "path": executable_path,
            "multicast_preference_set": truth(item.get("MulticastPreferenceSet")),
            "deny_multicast": truth(item.get("DenyMulticast")),
        }
    )


def is_allowed(entry):
    return entry["multicast_preference_set"] is True and entry["deny_multicast"] is False


def is_denied(entry):
    return entry["deny_multicast"] is True


def describe(entry):
    parts = []
    if entry["signing_identifier"]:
        parts.append(f"signing identifier {entry['signing_identifier']!r}")
    if entry["path"]:
        parts.append(f"path {entry['path']!r}")
    return ", ".join(parts) or "unknown entry"


matched = []
allowed = []
denied = []
path_identifier_mismatch = []
identifier_path_mismatch = []

for entry in entries:
    path_matches = entry["path"] in path_candidates if entry["path"] else False
    identifier_matches = expected_identifier is None or entry["signing_identifier"] == expected_identifier

    if path_matches and identifier_matches:
        matched.append(entry)
        if is_allowed(entry):
            allowed.append(entry)
        elif is_denied(entry):
            denied.append(entry)
    elif path_matches and expected_identifier is not None and is_allowed(entry):
        path_identifier_mismatch.append(entry)
    elif (
        expected_identifier is not None
        and entry["path"] is not None
        and entry["signing_identifier"] == expected_identifier
        and is_allowed(entry)
    ):
        identifier_path_mismatch.append(entry)

if allowed:
    print(f"Local Network access is granted for {label}")
    sys.exit(0)

if denied:
    print(f"Local Network access is denied for {label}.")
elif matched:
    print(f"Local Network access is not granted for {label}.")
elif path_identifier_mismatch:
    entry = path_identifier_mismatch[0]
    print(
        "Local Network access grant exists for this path, but its signing "
        f"identifier does not match {expected_identifier!r}: {describe(entry)}."
    )
elif identifier_path_mismatch:
    entry = identifier_path_mismatch[0]
    print(
        "Local Network access grant exists for this signing identifier, but "
        f"for a different path: {describe(entry)}."
    )
else:
    print(f"No Local Network access entry found for {label}.")

sys.exit(1)
PY
