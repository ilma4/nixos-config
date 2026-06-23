# keyboard-watcher (macOS)

An event-driven launchd agent that re-applies a key remapping to the Logitech MX
Keys Mini **every time it connects** — on login, after sleep, after a Bluetooth
re-pair, or after re-plugging USB. The remapping is applied **in-process** (no
`hidutil` subprocess): the watcher sets the same `UserKeyMapping` property that
`hidutil property --set` writes, using IOKit directly.

## Why

`hidutil` key mappings are **per-connection**: macOS discards them whenever the
keyboard disconnects. The previous approach — a one-shot `keyboard-remap` agent —
only polled for the keyboard once at login and then exited, so the custom mapping
was lost on the first disconnect and not restored until the next login.

`keyboard-watcher` closes that gap. It is a small Rust daemon that uses
`IOHIDManager`, whose device-matching callback fires for **already-connected and
newly connected** matching devices. On each connect it re-applies the remapping, so
the mapping is restored immediately on every reconnect. Because it also fires for
the already-connected keyboard at login, it fully **replaces** the old one-shot
`keyboard-remap` poll.

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

- builds the Rust program at nix-darwin build time via
  `pkgs.makeRustPlatform` + `buildRustPackage` (same pattern as
  `overlays/monitor-input-overlay.nix`), and
- defines the `keyboard-watcher` launchd agent, passing it the vendor id, product
  id, and the `keyMappings` pairs as arguments.

The Rust crate lives next to the module:

```
darwin-modules/
  keyboard-watcher.nix          # module: package build + launchd agent
  keyboard-watcher/
    Cargo.toml                  # edition 2024; deps: objc2-io-kit, objc2-core-foundation
    Cargo.lock                  # committed; buildRustPackage vendors deps offline by checksum
    src/main.rs                 # IOHIDManager watcher + in-process remap
```

Dependencies are only `objc2-io-kit` (`hid` for `IOHIDManager`, `hidsystem` for
`IOHIDEventSystemClient`/`IOHIDServiceClient`) and `objc2-core-foundation`
(`CFArray`/`CFDictionary`/`CFNumber`/`CFRunLoop`/`CFString`/`std`), which link IOKit
and CoreFoundation directly. No extra `buildInputs` are needed under the modern
Apple SDK in nixpkgs (the default `apple-sdk` provides the frameworks).

### Release profile (small binary / low RAM)

`Cargo.toml` sets a size-oriented `[profile.release]` because the watcher spends
nearly all its time blocked in `CFRunLoop`:

- `opt-level = "z"`, `lto = "fat"`, `codegen-units = 1` — smallest code,
- `panic = "abort"` — drops unwinding tables; a panic aborts and launchd's
  `KeepAlive` relaunches the agent,
- `strip = true` — strip symbols.

This keeps the binary small (~375K stripped).

## The program

`src/main.rs` takes a vendor id, a product id, and one or more `<src>:<dst>`
remappings — e.g. `keyboard-watcher 0x46d 0xb369 0x700000064:0x700000035 …` (all
values in decimal or `0x` hex) — and:

1. builds a `{VendorID, ProductID}` matching dictionary,
2. registers an `IOHIDManager` device-matching callback and schedules it on the
   current `CFRunLoop`,
3. on each connect, creates an `IOHIDEventSystemClient`, finds every HID **event
   service** matching the vendor/product, and sets their `UserKeyMapping`
   property — the same property `hidutil property --matching … --set` writes,
4. blocks in `CFRunLoop::run()` for the life of the process.

The remap **must** be applied at the HID event-system level (the
`IOHIDServiceClient`), not on the raw `IOHIDDevice`: setting `UserKeyMapping`
directly on the device via `IOHIDDeviceSetProperty` returns success but has no
effect — macOS consumes the property on the service. This is why the watcher
enumerates services and sets the property on each match, exactly as `hidutil`
does internally.

It only reads device/service **properties** (e.g. `Product`, `VendorID`) and sets
the `UserKeyMapping` configuration property; it never opens devices for input, so
it does **not** require Input Monitoring permission.

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

# Build the full darwin system (catches Rust + link errors)
nix build .#darwinConfigurations.quicksilver.system

# Switch (only when you actually want it live)
nix-rebuild
```

After switching:

```sh
# Should show: watching HID device 046d:b369
cat /tmp/keyboard-watcher.log

# Re-power the keyboard, then confirm the mapping is live:
/usr/bin/hidutil property \
  --matching '{"VendorID":0x46d,"ProductID":0xb369}' \
  --get UserKeyMapping
```

Disconnect and reconnect the keyboard — the log shows `keyboard connected: …`
followed by `applied N key remapping(s) to service "…"`, and the mapping reappears
immediately. This is the gap the old one-shot `keyboard-remap` poll could not cover.
