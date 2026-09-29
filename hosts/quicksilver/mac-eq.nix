{
  lib,
  pkgs,
  ...
}: let
  macEqSessionWatcher = pkgs.swiftPackages.stdenv.mkDerivation {
    pname = "mac-eq-network-watcher";
    version = "0.1.0";
    src = ./mac-eq-session-watcher;

    nativeBuildInputs = [pkgs.swift];
    dontConfigure = true;

    buildPhase = ''
      runHook preBuild
      swiftc -swift-version 5 -parse-as-library -O \
        -framework AppKit \
        -framework CoreGraphics \
        -o mac-eq-network-watcher \
        main.swift
      runHook postBuild
    '';

    installPhase = ''
      runHook preInstall
      install -Dm755 mac-eq-network-watcher $out/bin/mac-eq-network-watcher
      runHook postInstall
    '';

    meta = {
      description = "Run MacEQ while the user session is active";
      mainProgram = "mac-eq-network-watcher";
      platforms = lib.platforms.darwin;
    };
  };
in {
  launchd.user.agents.mac-eq-auto-start = {
    serviceConfig = {
      ProgramArguments = [(lib.getExe macEqSessionWatcher)];
      RunAtLoad = true;
      KeepAlive = true;
      StandardOutPath = "/tmp/mac-eq-auto-start.log";
      StandardErrorPath = "/tmp/mac-eq-auto-start.err.log";
    };
  };
}
