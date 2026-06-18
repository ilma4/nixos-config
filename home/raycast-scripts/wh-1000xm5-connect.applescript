#!/usr/bin/osascript

# Required parameters:
# @raycast.schemaVersion 1
# @raycast.title Connect WH-1000XM5
# @raycast.mode silent

# Optional parameters:
# @raycast.icon 🎧
# @raycast.packageName Bluetooth
# @raycast.description Connect to Sony WH-1000XM5 headphones

property blueutil : "/Users/ilma4/.nix-profile/bin/blueutil"
property notifier : "/Users/ilma4/.nix-profile/bin/terminal-notifier"
property deviceAddress : "AC:80:0A:93:B1:08"
property notifyGroup : "wh-1000xm5-connect"

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
	set connectedState to do shell script quoted form of blueutil & " --is-connected " & deviceAddress
	if connectedState is "1" then
		showNotification("Bluetooth", "WH-1000XM5 already connected")
	else
		do shell script quoted form of blueutil & " --connect " & deviceAddress
		showNotification("Bluetooth", "Connected to WH-1000XM5")
	end if
on error errorMessage
	showNotification("WH-1000XM5 connection failed", errorMessage)
end try
