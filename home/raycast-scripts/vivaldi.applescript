#!/usr/bin/osascript

# Required parameters:
# @raycast.schemaVersion 1
# @raycast.title Vivaldi new Window
# @raycast.mode silent

# Optional parameters:
# @raycast.icon V

property notifier : "/Users/ilma4/.nix-profile/bin/terminal-notifier"
property notifyGroup : "vivaldi-new-window"

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
		if (name of processes) contains "Vivaldi" then
			tell application "Vivaldi"
				make new window
				activate
			end tell
		else
			do shell script "open -a Vivaldi"
		end if
	end tell
on error errorMessage
	showNotification("Vivaldi launch failed", errorMessage)
end try
