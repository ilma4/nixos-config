#!/usr/bin/osascript

# Required parameters:
# @raycast.schemaVersion 1
# @raycast.title External Mic
# @raycast.mode silent

# Optional parameters:
# @raycast.icon 🎙️
# @raycast.packageName Audio
# @raycast.description Connect WH-1000XM5, then switch input to External Microphone

property connectScript : "/Users/ilma4/Scripts/wh-1000xm5-connect.applescript"
property switchAudio : "/Users/ilma4/.nix-profile/bin/SwitchAudioSource"
property notifier : "/Users/ilma4/.nix-profile/bin/terminal-notifier"
property inputDevice : "External Microphone"
property notifyGroup : "mic-switch"

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

# Connect the headphones first; the connect script notifies about its own result.
do shell script "osascript " & quoted form of connectScript

# Switch the input device regardless of whether the connection succeeded.
try
	do shell script quoted form of switchAudio & " -t input -s " & quoted form of inputDevice
	showNotification("Input device", inputDevice)
on error errorMessage
	showNotification("Input switch failed", errorMessage)
end try
