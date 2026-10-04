{
  config,
  pkgs,
  pkgs-unstable,
  ...
}: let
  modelsDirectory = "/Volumes/Extra/llama-cpp";
  volumeWatcher = pkgs.swiftPackages.stdenv.mkDerivation {
    pname = "llama-volume-watch";
    version = "0.1.0";
    dontUnpack = true;
    dontConfigure = true;
    nativeBuildInputs = [pkgs.swift];
    buildPhase = ''
      runHook preBuild
      swiftc -swift-version 5 -O -o llama-volume-watch ${./llama-volume-watch.swift}
      runHook postBuild
    '';
    installPhase = ''
      runHook preInstall
      install -Dm755 llama-volume-watch "$out/bin/llama-volume-watch"
      runHook postInstall
    '';
  };
in {
  home.packages = [pkgs-unstable.llama-cpp];

  # Imported only by ilma4-home.nix: this runs in ilma4's login session.
  # KeepAlive alone cannot stop a running job when a volume disappears.
  launchd.agents.llama-cpp = {
    enable = true;
    config = {
      # Keep unrelated models in the user's default cache out of this router.
      EnvironmentVariables.LLAMA_CACHE = "${modelsDirectory}/.cache/llama.cpp";
      ProgramArguments = [
        "${volumeWatcher}/bin/llama-volume-watch"
        "/Volumes/Extra"
        modelsDirectory
        "${pkgs-unstable.llama-cpp}/bin/llama-server"
        "--host"
        "0.0.0.0"
        "--port"
        "8080"
        "--models-dir"
        modelsDirectory
        "--models-preset"
        "${modelsDirectory}/models.ini"
        "--models-max"
        "1"
      ];
      RunAtLoad = true;
      StartOnMount = true;
      KeepAlive.SuccessfulExit = false;
      ThrottleInterval = 10;
      ExitTimeOut = 20;
      StandardOutPath = "${config.home.homeDirectory}/Library/Logs/llama-cpp.log";
      StandardErrorPath = "${config.home.homeDirectory}/Library/Logs/llama-cpp.log";
    };
  };
}
