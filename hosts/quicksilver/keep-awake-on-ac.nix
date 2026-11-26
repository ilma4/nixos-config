{
  lib,
  pkgs,
  ...
}: let
  keepAwakeOnAC = pkgs.stdenv.mkDerivation {
    pname = "keep-awake-on-ac";
    version = "1.0.0";
    src = ./keep-awake-on-ac.swift;
    nativeBuildInputs = [pkgs.swift];
    dontUnpack = true;
    dontConfigure = true;
    buildPhase = ''
      runHook preBuild
      swiftc -O -framework IOKit \
        -import-objc-header ${./keep-awake-on-ac-bridging.h} \
        "$src" -o keep-awake-on-ac
      runHook postBuild
    '';
    installPhase = ''
      runHook preInstall
      install -Dm755 keep-awake-on-ac "$out/bin/keep-awake-on-ac"
      runHook postInstall
    '';
    meta.mainProgram = "keep-awake-on-ac";
  };
in {
  launchd.daemons.keep-awake-on-ac = {
    command = lib.getExe keepAwakeOnAC;
    serviceConfig = {
      KeepAlive = true;
      StandardErrorPath = "/var/log/keep-awake-on-ac.log";
    };
  };
}
