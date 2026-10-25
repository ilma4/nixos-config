#!/usr/bin/osascript

# Required parameters:
# @raycast.schemaVersion 1
# @raycast.title Brave new Window
# @raycast.mode silent

# Optional parameters:
# @raycast.icon icons/brave.png

property notifier : (POSIX path of (path to home folder)) & ".nix-profile/bin/terminal-notifier"
property notifyGroup : "brave-new-window"

# macOS `display notification` cannot auto-dismiss, so post via terminal-notifier
# under a group id and remove that group after 3s (detached, so we return now).
on showNotification(theTitle, theMessage)
	do shell script quoted form of notifier & ¬
		" -group " & quoted form of notifyGroup & ¬
		" -title " & quoted form of theTitle & ¬
		" -message " & quoted form of theMessage
	do shell script "nohup sh -c 'sleep 3; " & notifier & ¬
		" -remove " & notifyGroup & "' >/dev/null 2>&1 &"
end showNotification

try
	tell application "System Events"
		if (name of processes) contains "Brave Browser" then
			tell application "Brave Browser"
				make new window
				activate
			end tell
		else
			do shell script "open -a 'Brave Browser'"
		end if
	end tell
on error errorMessage
	showNotification("Brave Browser launch failed", errorMessage)
end try
