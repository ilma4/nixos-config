{
  lib,
  pkgs,
  pkgs-unstable,
  ...
}: let
  port = 8080;
  modelName = "Qwen3.5-9B-UD-Q4_K_XL";
  qwen35-9b = pkgs.fetchurl {
    url = "https://huggingface.co/unsloth/Qwen3.5-9B-GGUF/resolve/24fadbaba5891f3965d66ea0e2e4aa259cd38c77/${modelName}.gguf";
    hash = "sha256-b10wZmwtiuFqMG5hbZU0Hc88xGgQ34TX5vWn0eTBspM=";
  };
  qwen35-9b-mmproj = pkgs.fetchurl {
    url = "https://huggingface.co/unsloth/Qwen3.5-9B-GGUF/resolve/24fadbaba5891f3965d66ea0e2e4aa259cd38c77/mmproj-F16.gguf";
    hash = "sha256-9w3DUJBTlisNDT7op+rOv11gqlYMrXglSuhphRauAp8=";
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
      models.${modelName} = {
        cmd = "${llamaServerBase} -m ${qwen35-9b}";
        aliases = ["qwen3.5-9b"];
      };
      models."qwen-3.5-9b-vision" = {
        cmd = "${llamaServerBase} -m ${qwen35-9b} --mmproj ${qwen35-9b-mmproj}";
        aliases = ["qwen3.5-9b-vision"];
      };
    };
  };

  networking.firewall.extraCommands = ''
    iptables -A nixos-fw -p tcp -s 192.168.1.0/24 --dport ${toString port} -j nixos-fw-accept
  '';

  systemd.services.llama-swap.serviceConfig.SupplementaryGroups = ["render" "video"];
}
