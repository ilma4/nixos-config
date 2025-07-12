#!/usr/bin/osascript

# Required parameters:
# @raycast.schemaVersion 1
# @raycast.title Firefox
# @raycast.mode compact

# Optional parameters:
# @raycast.icon F


tell application "System Events"
    if (name of processes) contains "Firefox" then
        do shell script "/opt/homebrew/bin/firefox"
    else
        do shell script "open -a Firefox"
    end if
end tell
