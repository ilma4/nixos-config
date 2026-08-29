#!/usr/bin/env bash
# Copy the current user's meaningful iTerm2 preferences into the shared template.

set -euo pipefail

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "Error: iTerm2 preferences can only be copied on macOS." >&2
  exit 1
fi

if ! command -v python3 >/dev/null 2>&1; then
  echo "Error: python3 is required." >&2
  exit 1
fi

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
repo_root="$(cd -- "${script_dir}/.." && pwd -P)"
destination="${repo_root}/dotfiles/iterm2/preferences.json"
exported_plist="$(mktemp "${TMPDIR:-/tmp}/iterm2-preferences.XXXXXX")"
trap 'rm -f -- "$exported_plist"' EXIT

if ! /usr/bin/defaults export com.googlecode.iterm2 - >"$exported_plist"; then
  echo "Error: failed to export the current user's iTerm2 preferences." >&2
  exit 1
fi

python3 - "$exported_plist" "$destination" "$HOME" <<'PY'
import json
import os
import plistlib
import sys
import tempfile
from pathlib import Path

source = Path(sys.argv[1])
target = Path(sys.argv[2])
home = sys.argv[3]

with source.open("rb") as file:
    preferences = plistlib.load(file)

if not isinstance(preferences, dict):
    raise SystemExit("Error: exported iTerm2 preferences are not a dictionary.")

# Exclude transient Cocoa window state, iTerm2 runtime bookkeeping, updater
# metadata, migration flags, and the ephemeral Secure Keyboard Entry state.
exclude_prefixes = (
    "NS",
    "NoSync",
    "Apple",
    "SU",
    "UKCrashReporter",
    "NeverWarnAboutShortLivedSessions",
)
exclude_exact = {
    "HotkeyMigratedFromSingleToMulti",
    "Secure Input",
    "iTerm Version",
}

# These prefixed values are actual user preferences rather than transient state.
include_overrides = {
    "AppleAntiAliasingThreshold",
    "ApplePressAndHoldEnabled",
    "AppleScrollAnimationEnabled",
    "AppleSmoothFixedFontsSizeThreshold",
    "AppleWindowTabbingMode",
    "NSScrollAnimationEnabled",
    "NSScrollViewShouldScrollUnderTitlebar",
    "NoSyncIgnoreSystemWindowRestoration",
    "NoSyncNewTabFromTmuxOpensTmux",
    "NoSyncScrollingHorizontally",
    "NoSyncSuppressDownloadConfirmation",
    "NoSyncSuppressPromptToEnableResizing",
    "NoSyncWindowRestoresWorkspaceAtLaunch",
    "SUEnableAutomaticChecks",
    "SUSendProfileInfo",
}

managed = {
    key: value
    for key, value in preferences.items()
    if key in include_overrides
    or (
        key not in exclude_exact
        and not key.startswith(exclude_prefixes)
        and not key.endswith("_selection")
    )
}


def replace_home(value):
    if isinstance(value, str):
        return value.replace(home, "@HOME@")
    if isinstance(value, list):
        return [replace_home(item) for item in value]
    if isinstance(value, dict):
        return {key: replace_home(item) for key, item in value.items()}
    return value


managed = replace_home(managed)
try:
    rendered = json.dumps(managed, indent=2, sort_keys=True, ensure_ascii=False) + "\n"
except TypeError as error:
    raise SystemExit(f"Error: a managed iTerm2 preference cannot be represented in JSON: {error}") from error

current = target.read_text() if target.exists() else None
if rendered == current:
    print(f"iTerm2 settings are already up to date: {target}")
    raise SystemExit(0)

target.parent.mkdir(parents=True, exist_ok=True)
with tempfile.NamedTemporaryFile(
    mode="w",
    encoding="utf-8",
    dir=target.parent,
    prefix=f".{target.name}.",
    delete=False,
) as file:
    temporary_path = Path(file.name)
    file.write(rendered)

try:
    os.replace(temporary_path, target)
except BaseException:
    temporary_path.unlink(missing_ok=True)
    raise

profile_count = len(managed.get("New Bookmarks", []))
print(f"Copied {len(managed)} iTerm2 settings and {profile_count} profiles to {target}")
PY
