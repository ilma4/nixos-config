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

  keyboard-watcher = pkgs.stdenv.mkDerivation {
    pname = "keyboard-watcher";
    version = "0.1.0";
    src = ./keyboard-watcher;
    nativeBuildInputs = [pkgs.swift];
    dontConfigure = true;
    buildPhase = ''
      runHook preBuild

      # nixpkgs currently provides a Swift 5 compiler on Darwin. Compile in
      # Swift 6 mode whenever the selected compiler supports it, while still
      # allowing this flake to build with the current compiler. The source is
      # written to pass Swift 6's complete concurrency checks.
      if printf %s "" | swiftc -swift-version 6 -typecheck - >/dev/null 2>&1; then
        swiftVersion=6
      else
        swiftVersion=5
      fi

      swiftc \
        -swift-version "$swiftVersion" \
        -warn-concurrency \
        -strict-concurrency=complete \
        -O \
        -whole-module-optimization \
        -framework IOKit \
        -framework CoreFoundation \
        -o keyboard-watcher \
        src/main.swift

      runHook postBuild
    '';
    installPhase = ''
      runHook preInstall
      install -Dm755 keyboard-watcher "$out/bin/keyboard-watcher"
      runHook postInstall
    '';
    meta = {
      description = "Watch a specific HID keyboard and re-apply key remapping on connect";
      mainProgram = "keyboard-watcher";
      platforms = lib.platforms.darwin;
    };
  };

  # hidutil-style key remappings, applied in-process by the watcher (no hidutil
  # subprocess). macOS resets these whenever the keyboard disconnects, so the
  # watcher re-applies them on every (re)connect. Each entry is "<src>:<dst>"
  # using the 64-bit HID usage codes hidutil expects:
  #   Non-US \| (ISO key by left Shift) 0x700000064 -> Grave/Tilde (`) 0x700000035
  #   Grave/Tilde (`)                   0x700000035 -> Fn / Globe       0xFF00000003
  keyMappings = [
    "0x700000064:0x700000035"
    "0x700000035:0xFF00000003"
  ];
in {
  options.i4.keyboard-watcher.enable =
    lib.mkEnableOption "watch the Logitech MX Keys Mini and re-apply key remapping on every connect";

  config = lib.mkIf cfg.enable {
    # Event-driven and long-lived: re-applies the mapping on every (re)connect for
    # the whole login session, including the already-connected keyboard at login.
    # Covers sleep/wake, Bluetooth re-pair and USB replug — so no separate
    # poll-at-login agent is needed.
    launchd.agents.keyboard-watcher.serviceConfig = {
      ProgramArguments =
        [
          (lib.getExe keyboard-watcher)
          vendorId
          productId
        ]
        ++ keyMappings;
      RunAtLoad = true;
      KeepAlive = true; # long-running daemon: relaunch if it ever exits
      StandardOutPath = "/tmp/keyboard-watcher.log";
      StandardErrorPath = "/tmp/keyboard-watcher.log";
    };
  };
}
