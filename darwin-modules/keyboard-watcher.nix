{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.i4.keyboard-watcher;

  # Logitech MX Keys Mini.
  vendorId = "0x46d";
  productId = "0xb369";
  deviceMatch = ''{"VendorID":${vendorId},"ProductID":${productId}}'';

  rustPlatform = pkgs.makeRustPlatform {
    cargo = pkgs.rust-bin.stable.latest.default;
    rustc = pkgs.rust-bin.stable.latest.default;
  };

  keyboard-watcher = rustPlatform.buildRustPackage {
    pname = "keyboard-watcher";
    version = "0.1.0";
    src = ./keyboard-watcher;
    cargoLock.lockFile = ./keyboard-watcher/Cargo.lock;
    meta = {
      description = "Watch a specific HID keyboard and re-apply key remapping on connect";
      mainProgram = "keyboard-watcher";
      platforms = lib.platforms.darwin;
    };
  };

  # hidutil key mappings are per-connection and reset whenever the keyboard
  # disconnects, so this is applied on every (re)connect:
  #   Non-US \| (ISO key by left Shift) 0x700000064 -> Grave/Tilde (`) 0x700000035
  #   Grave/Tilde (`)                   0x700000035 -> Fn / Globe       0xFF00000003
  keyMapping = ''
    {
      "UserKeyMapping": [
        {
          "HIDKeyboardModifierMappingSrc": 0x700000064,
          "HIDKeyboardModifierMappingDst": 0x700000035
        },
        {
          "HIDKeyboardModifierMappingSrc": 0x700000035,
          "HIDKeyboardModifierMappingDst": 0xFF00000003
        }
      ]
    }
  '';

  remap-script = pkgs.writeShellScript "mx-keys-mini-remap" ''
    set -euo pipefail
    echo "$(/bin/date): applying MX Keys Mini key mapping"
    /usr/bin/hidutil property --matching '${deviceMatch}' --set '${keyMapping}'
    echo "$(/bin/date): key mapping applied"
  '';
in {
  options.i4.keyboard-watcher.enable =
    lib.mkEnableOption "watch the Logitech MX Keys Mini and re-apply key remapping on every connect";

  config = lib.mkIf cfg.enable {
    # Event-driven and long-lived: re-applies the mapping on every (re)connect for
    # the whole login session, including the already-connected keyboard at login.
    # Covers sleep/wake, Bluetooth re-pair and USB replug — so no separate
    # poll-at-login agent is needed.
    launchd.agents.keyboard-watcher.serviceConfig = {
      ProgramArguments = [
        (lib.getExe keyboard-watcher)
        vendorId
        productId
        "${remap-script}"
      ];
      RunAtLoad = true;
      KeepAlive = true; # long-running daemon: relaunch if it ever exits
      StandardOutPath = "/tmp/keyboard-watcher.log";
      StandardErrorPath = "/tmp/keyboard-watcher.log";
    };
  };
}
