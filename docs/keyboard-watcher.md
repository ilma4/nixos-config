# keyboard-watcher (macOS)

An event-driven launchd agent that re-applies a key remapping to the Logitech MX
Keys Mini **every time it connects** — on login, after sleep, after a Bluetooth
re-pair, or after re-plugging USB. The remapping is applied **in-process** (no
`hidutil` subprocess): the watcher sets the same `UserKeyMapping` property that
`hidutil property --set` writes, using IOKit directly. The configured mappings
include special characters and need **Input Monitoring permission**. If permission
is granted after the keyboard connects, the watcher automatically re-applies the
mappings without requiring another connection or a manual restart.

## Why

`hidutil` key mappings are **per-connection**: macOS discards them whenever the
keyboard disconnects. The previous approach — a one-shot `keyboard-remap` agent —
only polled for the keyboard once at login and then exited, so the custom mapping
was lost on the first disconnect and not restored until the next login.

`keyboard-watcher` closes that gap. It asks IOKit to notify it whenever a matching
HID device appears in the IORegistry (including the one already connected at
launch), and re-applies the remapping on each such event. Because it also fires
for the already-connected keyboard at startup, it fully **replaces** the old
one-shot `keyboard-remap` poll.

## What it remaps

Logitech MX Keys Mini — `VendorID 0x46d`, `ProductID 0xb369`:

| From                                   | To                |
| -------------------------------------- | ----------------- |
| Non-US `\|` (ISO key by left Shift, `0x700000064`) | Grave/Tilde `` ` `` (`0x700000035`) |
| Grave/Tilde `` ` `` (`0x700000035`)    | Fn / Globe (`0xFF00000003`) |

The mapping is declared as the `keyMappings` list (`"<src>:<dst>"` pairs of 64-bit
HID usage codes) in `darwin-modules/keyboard-watcher.nix` and passed to the watcher
as command-line arguments.

## How it's built

Everything is wired in a single self-contained module,
`darwin-modules/keyboard-watcher.nix`, which:

- builds the Swift program at nix-darwin build time with the Swift compiler and
  the system `IOKit` and `CoreFoundation` frameworks, and
- defines the `keyboard-watcher` launchd agent, passing it the vendor id, product
  id, and the `keyMappings` pairs as arguments.

The Swift source lives next to the module:

```
darwin-modules/
  keyboard-watcher.nix          # module: package build + launchd agent
  keyboard-watcher/
    src/main.swift              # IORegistry watcher + in-process remap
```

The program has no third-party dependencies. Swift imports the Apple SDK's
`IOKit`, `IOKit.hidsystem`, `CoreFoundation`, `Dispatch`, and `Foundation`
modules directly. The Nix build links `IOKit` and `CoreFoundation`; the default
Apple SDK in nixpkgs provides both frameworks.

The source passes Swift 6's complete concurrency checks. The Nix build uses
Swift 6 language mode when the selected compiler supports it, and falls back to
Swift 5 language mode for nixpkgs revisions that still package Swift 5.10.

### Release build (small binary / low RAM)

The Nix build uses whole-module optimization because the watcher spends nearly
all its time waiting in `dispatchMain()`:

- `-O` — optimized code,
- `-whole-module-optimization` — enables cross-file optimization,
- `KeepAlive` — launchd relaunches the agent if it exits.

The binary is stripped by the Nix build where supported.

## The program

`src/main.swift` takes a vendor id, a product id, and one or more `<src>:<dst>`
remappings — e.g. `keyboard-watcher 0x46d 0xb369 0x700000064:0x700000035 …` (all
values in decimal or `0x` hex) — and:

1. builds a matching dictionary `{IOProviderClass: "IOHIDDevice", VendorID,
   ProductID}` (the same thing `IOServiceMatching` + a property filter produces),
2. creates an `IONotificationPort`, schedules its callbacks on the main dispatch
   queue, and registers a `kIOFirstMatchNotification` via
   `IOServiceAddMatchingNotification`,
3. drains the returned iterator once — which both arms the notification and
   handles a keyboard that is **already connected** at startup — and drains it
   again inside the callback on every later (re)connect,
4. on each match, creates an `IOHIDEventSystemClient`, finds every HID **event
   service** matching the vendor/product, and sets their `UserKeyMapping`
   property — the same property `hidutil property --matching … --set` writes,
5. checks Input Monitoring once per second while waiting for permission; when
   granted, re-enumerates connected devices and re-applies the mappings,
6. waits in `dispatchMain()` for the life of the process. Permission polling stops
   after permission is granted; ordinary connections remain event-driven.

### Reconnect race — why the apply retries

The notification fires when the keyboard's **`IOHIDDevice` IORegistry node**
appears, but the matching **`IOHIDEventSystem` service** (what step 4 enumerates)
is published a moment *later*. So on a fresh reconnect the first apply finds no
matching service. When that happens the watcher schedules another apply on the
main dispatch queue (every 200 ms for ~5 s, without blocking) until the service shows
up. The already-connected-at-startup case has the service present immediately and
applies on the first try.

### Permissions and recovery after approval

The obvious way to detect the keyboard is `IOHIDManager`, but **opening HID devices
requires the Input Monitoring privacy permission** (`kTCCServiceListenEvent`). A
background launchd job can't raise the approval prompt, and the grant is keyed to
the binary's code signature — which changes on every Nix rebuild — so an
`IOHIDManager`-based watcher fails with `kIOReturnNotPermitted` (`0xe00002e2`).

Watching the **IORegistry** with `IOServiceAddMatchingNotification` only observes
the registry; it never opens the device, so connection detection needs no Input
Monitoring. The remap itself **must** be applied at the HID event-system level (the
`IOHIDServiceClient`), not on the raw `IOHIDDevice` — setting `UserKeyMapping`
directly on the device via `IOHIDDeviceSetProperty` returns success but has no
effect. Setting it on the service (as `hidutil` does) is subject to Input Monitoring
checks for mappings involving alphanumeric keys or special characters. The HID
setter can report success even when the keyboard filter rejects the remapping.

Grant the watcher access in **System Settings → Privacy & Security → Input
Monitoring**. After a connection without permission, the watcher logs that it is
waiting and checks permission once per second, with no timeout. Granting permission
triggers a fresh apply for the already-connected keyboard, normally within about a
second. This permission recovery is independent of the five-second service
publication retry window and of the earlier setter's return value. If the keyboard
has disconnected in the meantime, recovery does nothing until it connects again.

Only one permission timer runs, even after repeated connection notifications. The
timer stops after approval and starts again if a later connection finds permission
missing. The watcher does not request permission or show approval prompts itself.

## Configuration

Enabled on quicksilver via the module option:

```nix
# hosts/quicksilver/quicksilver.nix
i4.keyboard-watcher.enable = true;
```

The launchd agent runs with `RunAtLoad = true` and `KeepAlive = true` (long-running
daemon, relaunched if it ever exits) and logs to `/tmp/keyboard-watcher.log`.

To target a different keyboard or change the mapping, edit `vendorId`/`productId`
and the `keyMappings` list in `darwin-modules/keyboard-watcher.nix`. Find a device's
IDs with `hidutil list`.

## Build & verify

```sh
# Evaluate all configs (catches module wiring errors)
./utils/flake-check.sh

# Build the full darwin system (catches Swift + link errors)
nix build .#darwinConfigurations.quicksilver.system

# Switch (only when you actually want it live)
nix-rebuild
```

After switching:

```sh
# Should show: watching for HID device 046d:b369
cat /tmp/keyboard-watcher.log

# Re-power the keyboard, then confirm the mapping is live:
/usr/bin/hidutil property \
  --matching '{"VendorID":0x46d,"ProductID":0xb369}' \
  --get UserKeyMapping
```

Disconnect and reconnect the keyboard — the log shows `matching HID device
connected (N IORegistry node(s)); applying remap` followed by `applied N key
remapping(s) to service "…"` (sometimes with a `event service not published yet;
retrying …` line in between, see the reconnect race above), and the mapping
reappears within a few seconds. This is the gap the old one-shot `keyboard-remap`
poll could not cover.

To verify permission recovery, connect the keyboard while the watcher lacks Input
Monitoring, wait longer than five seconds, then grant permission while leaving the
keyboard connected. The log should show `Input Monitoring permission granted;
retrying connected keyboard remap`, followed by the apply log. Check the mapping
with the `hidutil` command above and confirm both remapped keys work. No reconnect
or manual watcher restart should be necessary.
