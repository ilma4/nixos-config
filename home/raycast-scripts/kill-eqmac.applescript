#!/usr/bin/osascript

# Required parameters:
# @raycast.schemaVersion 1
# @raycast.title Kill eqMac
# @raycast.mode silent

# Optional parameters:
# @raycast.icon 🎚️
# @raycast.packageName Audio
# @raycast.description Stop the eqMac app, including an instance owned by another user

# eqMac.app runs in a login user's session. Its owner (e.g. ilma4) can stop it
# directly, so no root is needed there; any other user (e.g. malakhov) must
# escalate with sudo. malakhov is granted passwordless sudo for exactly this
# command via security.sudo.extraConfig in hosts/quicksilver/quicksilver.nix.
set currentUser to do shell script "/usr/bin/id -un"

set eqmacPid to ""
try
	set eqmacPid to do shell script "/usr/bin/pgrep -x eqMac | /usr/bin/head -1"
end try

if eqmacPid is not "" then
	set eqmacOwner to do shell script "/bin/ps -o user= -p " & eqmacPid
	if eqmacOwner is currentUser then
		do shell script "/usr/bin/pkill -x eqMac"
	else
		do shell script "/usr/bin/sudo -n /usr/bin/pkill -x eqMac"
	end if
end if
