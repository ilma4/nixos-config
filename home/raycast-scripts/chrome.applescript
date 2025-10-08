#!/usr/bin/osascript

# Required parameters:
# @raycast.schemaVersion 1
# @raycast.title Chrome new Window
# @raycast.mode compact

# Optional parameters:
# @raycast.icon G


tell application "System Events"
    if (name of processes) contains "Google Chrome" then
        tell application "Google Chrome"
            make new window
            activate
        end tell
    else
        do shell script "open -a Google Chrome"
    end if
end tell
