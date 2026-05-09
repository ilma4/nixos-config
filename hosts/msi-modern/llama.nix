{
  lib,
  pkgs,
  pkgs-unstable,
  ...
}: let
  port = 8080;
  qwen35-9b-modelName = "Qwen3.5-9B-UD-Q4_K_XL";
  qwen35-9b = pkgs.fetchurl {
    url = "https://huggingface.co/unsloth/Qwen3.5-9B-GGUF/resolve/24fadbaba5891f3965d66ea0e2e4aa259cd38c77/${qwen35-9b-modelName}.gguf";
    hash = "sha256-b10wZmwtiuFqMG5hbZU0Hc88xGgQ34TX5vWn0eTBspM=";
  };
  qwen35-9b-mmproj = pkgs.fetchurl {
    url = "https://huggingface.co/unsloth/Qwen3.5-9B-GGUF/resolve/24fadbaba5891f3965d66ea0e2e4aa259cd38c77/mmproj-F16.gguf";
    hash = "sha256-9w3DUJBTlisNDT7op+rOv11gqlYMrXglSuhphRauAp8=";
  };
  gemma4-e4b-modelName = "gemma-4-E4B-it-UD-Q4_K_XL";
  gemma4-e4b-revision = "653803f092503c04a65164346f3208a36e707693";
  gemma4-e4b = pkgs.fetchurl {
    url = "https://huggingface.co/unsloth/gemma-4-E4B-it-GGUF/resolve/${gemma4-e4b-revision}/${gemma4-e4b-modelName}.gguf";
    hash = "sha256-MNHnlJWXo0RnJgZOgLh2/Rtcukqm7sU9J6+kIOcx+zY=";
  };
  gemma4-e4b-mmproj = pkgs.fetchurl {
    url = "https://huggingface.co/unsloth/gemma-4-E4B-it-GGUF/resolve/${gemma4-e4b-revision}/mmproj-F16.gguf";
    hash = "sha256-3fRsIdcHjpUzjPwiMGsZsnaimlrQiQI0Sd1U1LYXClE=";
  };
  llamaCpp = pkgs-unstable.llama-cpp.override {vulkanSupport = true;};
  llamaServerBase = "${lib.getExe' llamaCpp "llama-server"} --host 127.0.0.1 --port \${PORT} -ngl 999 --no-webui";
in {
  services.llama-swap = {
    enable = true;
    package = pkgs-unstable.llama-swap;
    inherit port;
    openFirewall = false;
    settings = {
      healthCheckTimeout = 60;
      globalTTL = 300; # unload models after 5 minutes of inactivity
      models.${qwen35-9b-modelName} = {
        cmd = "${llamaServerBase} -m ${qwen35-9b}";
        aliases = ["qwen3.5-9b"];
      };
      models."qwen-3.5-9b-vision" = {
        cmd = "${llamaServerBase} -m ${qwen35-9b} --mmproj ${qwen35-9b-mmproj}";
        aliases = ["qwen3.5-9b-vision"];
      };
      models."gemma-4-e4b" = {
        cmd = "${llamaServerBase} -m ${gemma4-e4b} --mmproj ${gemma4-e4b-mmproj}";
        aliases = ["gemma4-e4b-it-vision"];
      };
    };
  };

  networking.firewall.extraCommands = ''
    iptables -A nixos-fw -p tcp -s 192.168.1.0/24 --dport ${toString port} -j nixos-fw-accept
  '';

  systemd.services.llama-swap.serviceConfig.SupplementaryGroups = ["render" "video"];
}
