#!/usr/bin/osascript

# Required parameters:
# @raycast.schemaVersion 1
# @raycast.title Nix Rebuild
# @raycast.mode silent

# Optional parameters:
# @raycast.icon 🔄
# @raycast.description Rebuild and switch to new Nix configuration

try
    do shell script "/Users/ilma4/.nix-profile/bin/nix-rebuild"
    display notification "Nix rebuild completed successfully" with title "Nix Rebuild"
on error errorMessage
    display notification "Nix rebuild failed: " & errorMessage with title "Nix Rebuild Error"
end try
