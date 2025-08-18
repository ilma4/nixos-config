#!/usr/bin/osascript

# Required parameters:
# @raycast.schemaVersion 1
# @raycast.title NAS mount toggle
# @raycast.mode compact

# Optional parameters:
# @raycast.icon F


set mountPoint to "/Users/ilma4/NoBackup/laat"

try
	do shell script "mount | grep " & quoted form of mountPoint
	-- Mounted, so unmount
	do shell script "umount " & quoted form of mountPoint
on error
	-- Not mounted, so mount
	do shell script "/Users/ilma4/.nix-profile/bin/rclone mount --daemon laat:/ " & quoted form of mountPoint
end try
