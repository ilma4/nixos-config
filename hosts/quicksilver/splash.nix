{
  config,
  lib,
  osConfig,
  pkgs,
  ...
}: let
  modelsDirectory = "${config.home.homeDirectory}/llama-cpp/models";
  homebrewPrefix = osConfig.homebrew.prefix or (lib.removeSuffix "/bin" osConfig.homebrew.brewPrefix);
  tailscale = lib.getExe' osConfig.services.tailscale.package "tailscale";
  port = "8080";
  allowedHostArgs = lib.concatMap (host: ["--allowed-host" host]) ["quicksilver" "quicksilver.tail09544e.ts.net"];
  logDirectory = "${config.home.homeDirectory}/Library/Logs";
  idleProxy = pkgs.rustPlatform.buildRustPackage {
    pname = "splash-idle-proxy";
    version = "1.0.0";
    src = ./splash-idle-proxy;
    cargoLock.lockFile = ./splash-idle-proxy/Cargo.lock;
  };
in {
  # Only the proxy stays resident in the login session. It starts Splash on
  # demand on a private Unix socket and stops the whole engine when idle.
  launchd.agents.splash = {
    enable = true;
    config = {
      ProgramArguments = [
        "${idleProxy}/bin/splash-idle-proxy"
        "--listen"
        "127.0.0.1:${port}"
        "--idle"
        "600"
      ] ++ allowedHostArgs ++ [
        "--"
        "${homebrewPrefix}/bin/splash"
        "serve"
        "--model"
        "unsloth/Qwen3.8-27B-GGUF:UD-Q4_K_XL"
        "--model-dir"
        "${modelsDirectory}/Qwen3.8-27B/Qwen3.8-27B-UD-Q4_K_XL.gguf"
        "--mmproj"
        "${modelsDirectory}/Qwen3.8-27B/mmproj-F16.gguf"
        "--draft-model"
        "${modelsDirectory}/drafts/Qwen3.8-27B-DFlash2"
        "--offline"
      ] ++ allowedHostArgs ++ [
        "--kv-format"
        "bf16"
        "--max-context"
        "65536"
        "--idle-release"
        "off"
        "--served-model-name"
        "Qwen3.8"
        "--served-model-name"
        "Qwen3.8-27B-UD-Q4_K_XL"
      ];
      RunAtLoad = true;
      KeepAlive = true;
      ThrottleInterval = 30;
      StandardOutPath = "${logDirectory}/splash.log";
      StandardErrorPath = "${logDirectory}/splash.log";
    };
  };

  # Quicksilver's userspace tailscaled has no local Tailscale interface to bind.
  # Use foreground Serve so launchd owns the forwarder's lifetime as well.
  launchd.agents.splash-tailscale = {
    enable = true;
    config = {
      ProgramArguments = [
        tailscale
        "serve"
        "--tcp=${port}"
        "tcp://127.0.0.1:${port}"
      ];
      RunAtLoad = true;
      KeepAlive = true;
      ThrottleInterval = 30;
      StandardOutPath = "${logDirectory}/splash-tailscale.log";
      StandardErrorPath = "${logDirectory}/splash-tailscale.log";
    };
  };
}
