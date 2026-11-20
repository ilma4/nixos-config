{
  pkgs,
  pkgs-unstable,
  ...
}: let
  port = 8080;
  modelName = "gemma-4-E4B-it-qat-UD-Q4_K_XL";
  modelUrl = "https://huggingface.co/unsloth/gemma-4-E4B-it-qat-GGUF/resolve/8c5a9e4fd5482e2be20fe0bf013b4c262a8f4265";
  model = pkgs.fetchurl {
    name = "${modelName}.gguf";
    url = "${modelUrl}/${modelName}.gguf?download=true";
    hash = "sha256-3w/U7gcHLGB8KaChy0+YkYQmzKEvRaJ3a91u5tCaTeM=";
  };
  mmproj = pkgs.fetchurl {
    name = "mmproj-F16.gguf";
    url = "${modelUrl}/mmproj-F16.gguf?download=true";
    hash = "sha256-aiVRWe5LAbME9jOlfwF919WmnTD/9Sq7JhS/CBPO8DQ=";
  };
in {
  services.llama-cpp = {
    enable = true;
    package = pkgs-unstable.llama-cpp-vulkan;
    host = "0.0.0.0";
    inherit port;
    # Start the router without loading a model; load Gemma on the first request.
    modelsPreset.${modelName} = {
      model = "${model}";
      mmproj = "${mmproj}";
      load-on-startup = false;
      n-gpu-layers = 999;
      sleep-idle-seconds = 300;
      temp = 1.0;
      top-p = 0.95;
      top-k = 64;
    };
    openFirewall = false;
    extraFlags = [
      "--no-ui"
    ];
  };

  networking.firewall.extraCommands = ''
    iptables -A nixos-fw -p tcp -s 192.168.1.0/24 --dport ${toString port} -j nixos-fw-accept
  '';

  systemd.services.llama-cpp.serviceConfig.SupplementaryGroups = ["render" "video"];
}
