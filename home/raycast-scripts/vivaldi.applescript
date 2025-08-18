#!/usr/bin/osascript

# Required parameters:
# @raycast.schemaVersion 1
# @raycast.title Vivaldi new Window
# @raycast.mode compact

# Optional parameters:
# @raycast.icon V


tell application "System Events"
    if (name of processes) contains "Vivaldi" then
        tell application "Vivaldi"
            make new window
            activate
        end tell
    else
        do shell script "open -a Vivaldi"
    end if
end tell
