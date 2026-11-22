{
  config,
  lib,
  osConfig,
  ...
}: let
  modelsDirectory = "${config.home.homeDirectory}/llama-cpp/models";
  homebrewPrefix = osConfig.homebrew.prefix or (lib.removeSuffix "/bin" osConfig.homebrew.brewPrefix);
  tailscale = lib.getExe' osConfig.services.tailscale.package "tailscale";
  port = "8080";
  logDirectory = "${config.home.homeDirectory}/Library/Logs";
in {
  # Run in malakhov's login session using the existing local model files.
  launchd.agents.splash = {
    enable = true;
    config = {
      ProgramArguments = [
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
        "--host"
        "127.0.0.1"
        "--port"
        port
        "--allowed-host"
        "quicksilver"
        "--allowed-host"
        "quicksilver.tail09544e.ts.net"
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
