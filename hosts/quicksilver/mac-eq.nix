{
  lib,
  pkgs,
  ...
}: let
  macEqNetworkWatcher = pkgs.swiftPackages.stdenv.mkDerivation {
    pname = "mac-eq-network-watcher";
    version = "0.1.0";
    src = ./mac-eq-network-watcher;

    nativeBuildInputs = [pkgs.swift];
    dontConfigure = true;

    buildPhase = ''
      runHook preBuild
      swiftc -swift-version 5 -parse-as-library -O \
        -framework AppKit \
        -framework Network \
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
      description = "Start MacEQ when Wi-Fi or Ethernet becomes connected";
      mainProgram = "mac-eq-network-watcher";
      platforms = lib.platforms.darwin;
    };
  };
in {
  launchd.user.agents.mac-eq-auto-start = {
    serviceConfig = {
      ProgramArguments = [(lib.getExe macEqNetworkWatcher)];
      RunAtLoad = true;
      KeepAlive = true;
      StandardOutPath = "/tmp/mac-eq-auto-start.log";
      StandardErrorPath = "/tmp/mac-eq-auto-start.err.log";
    };
  };
}
