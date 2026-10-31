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
      ProgramArguments = [
        "${volumeWatcher}/bin/model-volume-watch"
        "/Volumes/Extra"
        modelsDirectory
        "${homebrewPrefix}/bin/splash"
        "serve"
        "--model"
        "unsloth/Qwen3.8-27B-GGUF:UD-Q4_K_XL"
        "--model-dir"
        "${modelsDirectory}/models/Qwen3.8-27B/Qwen3.8-27B-UD-Q4_K_XL.gguf"
        "--mmproj"
        "${modelsDirectory}/models/Qwen3.8-27B/mmproj-F16.gguf"
        "--draft-model"
        "${modelsDirectory}/models/drafts/Qwen3.8-27B-DFlash2"
        "--offline"
        "--host"
        "0.0.0.0"
        "--port"
        "8080"
        "--kv-format"
        "bf16"
        "--max-context"
        "65536"
        "--idle-release"
        "10m"
        "--served-model-name"
        "Qwen3.8"
        "--served-model-name"
        "Qwen3.8-27B-UD-Q4_K_XL"
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
