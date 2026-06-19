#!/usr/bin/osascript

# Required parameters:
# @raycast.schemaVersion 1
# @raycast.title Built-in Mic
# @raycast.mode silent

# Optional parameters:
# @raycast.icon 💻
# @raycast.packageName Audio
# @raycast.description Connect WH-1000XM5, stop the ilma4 eqMac, switch input to the built-in microphone

property blueutil : "/Users/malakhov/.nix-profile/bin/blueutil"
property switchAudio : "/Users/malakhov/.nix-profile/bin/SwitchAudioSource"
property notifier : "/Users/malakhov/.nix-profile/bin/terminal-notifier"
property killEqmac : "/Users/malakhov/Scripts/kill-eqmac.applescript"
property deviceAddress : "AC:80:0A:93:B1:08"
property outputDevice : "WH-1000XM5"
# Built-in mic device name as reported by macOS on this MacBook Pro.
property inputDevice : "MacBook Pro Microphone"
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

# Connect the headphones; only proceed if they end up connected.
set headphonesReady to false
try
	set connectedState to do shell script quoted form of blueutil & " --is-connected " & deviceAddress
	if connectedState is "1" then
		set headphonesReady to true
	else
		do shell script quoted form of blueutil & " --connect " & deviceAddress
		set headphonesReady to true
	end if
on error errorMessage
	showNotification("WH-1000XM5 connection failed", errorMessage)
end try

if headphonesReady then
	# eqMac left running by the ilma4 session hijacks the headphone audio, so stop it.
	try
		do shell script "osascript " & quoted form of killEqmac
	end try
	# With eqMac gone, take the input first (this breaks macOS's HFP headset grab),
	# then route output to the real headphones at full quality.
	try
		assertInput(inputDevice)
		do shell script quoted form of switchAudio & " -t output -s " & quoted form of outputDevice
		showNotification("WH-1000XM5 ready", outputDevice & " out · " & inputDevice & " in")
	on error errorMessage
		showNotification("Audio switch failed", errorMessage)
	end try
end if
