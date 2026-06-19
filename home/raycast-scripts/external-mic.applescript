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

# Connecting the WH-1000XM5 makes macOS grab it as the input (HFP headset) a moment
# later, silently overriding a single switch. Re-assert the wanted input until it
# holds steady, signalling failure if it never sticks.
on assertInput(device)
	set q to quoted form of switchAudio
	do shell script "target=" & quoted form of device & "; held=0; ok=0; " & ¬
		"for i in $(seq 1 35); do " & ¬
		"cur=$(" & q & " -c -t input); " & ¬
		"if [ \"$cur\" = \"$target\" ]; then " & ¬
		"held=$((held + 1)); if [ \"$held\" -ge 10 ]; then ok=1; break; fi; " & ¬
		"else " & q & " -t input -s \"$target\" >/dev/null 2>&1; held=0; fi; " & ¬
		"/bin/sleep 0.2; done; [ \"$ok\" = 1 ]"
end assertInput

# Connect the headphones first; the connect script notifies about its own result.
do shell script "osascript " & quoted form of connectScript

# Switch (and hold) the input device regardless of whether the connection succeeded.
try
	assertInput(inputDevice)
	showNotification("Input device", inputDevice)
on error errorMessage
	showNotification("Input switch failed", errorMessage)
end try
