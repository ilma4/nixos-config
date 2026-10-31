{
  config,
  pkgs,
  lib,
  osConfig,
  ...
}: let
  modelsDirectory = "/Volumes/Extra/llama-cpp";
  homebrewPrefix = osConfig.homebrew.prefix or (lib.removeSuffix "/bin" osConfig.homebrew.brewPrefix);
  volumeWatcher = pkgs.swiftPackages.stdenv.mkDerivation {
    pname = "model-volume-watch";
    version = "0.1.0";
    dontUnpack = true;
    dontConfigure = true;
    nativeBuildInputs = [pkgs.swift];
    buildPhase = ''
      runHook preBuild
      swiftc -swift-version 5 -O -o model-volume-watch ${./model-volume-watch.swift}
      runHook postBuild
    '';
    installPhase = ''
      runHook preInstall
      install -Dm755 model-volume-watch "$out/bin/model-volume-watch"
      runHook postInstall
    '';
  };
in {
  # Imported only by ilma4-home.nix: this runs in ilma4's login session.
  # KeepAlive alone cannot stop a running job when a volume disappears.
  launchd.agents.splash = {
    enable = true;
    config = {
      EnvironmentVariables.SPLASH_BIN = "${homebrewPrefix}/bin/splash";
      ProgramArguments = [
        "${volumeWatcher}/bin/model-volume-watch"
        "/Volumes/Extra"
        modelsDirectory
        "${pkgs.llama-swap}/bin/llama-swap"
        "-config"
        "${modelsDirectory}/splash.yaml"
        "-listen"
        "0.0.0.0:8080"
      ];
      RunAtLoad = true;
      StartOnMount = true;
      KeepAlive.SuccessfulExit = false;
      ThrottleInterval = 10;
      ExitTimeOut = 20;
      StandardOutPath = "${config.home.homeDirectory}/Library/Logs/splash.log";
      StandardErrorPath = "${config.home.homeDirectory}/Library/Logs/splash.log";
    };
  };
}
