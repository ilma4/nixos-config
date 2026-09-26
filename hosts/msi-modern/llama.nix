{
  pkgs,
  pkgs-unstable,
  ...
}: let
  port = 8080;
  modelName = "gemma-4-12B-it-qat-UD-Q4_K_XL";
  model = pkgs.fetchurl {
    name = "${modelName}.gguf";
    url = "https://huggingface.co/unsloth/gemma-4-12B-it-qat-GGUF/resolve/main/${modelName}.gguf?download=true";
    hash = "sha256-kP1E4p4NfP/rD9ANxzz9q57QsOlTBuz3gh6mNMlAw3A=";
  };
  mmproj = pkgs.fetchurl {
    name = "mmproj-F16.gguf";
    url = "https://huggingface.co/unsloth/gemma-4-12B-it-qat-GGUF/resolve/main/mmproj-F16.gguf?download=true";
    hash = "sha256-7MTpMSjag2O32/IZPquYzxFCNT9SzqoMlcCHKZeqrdM=";
  };
in {
  services.llama-cpp = {
    enable = true;
    package = pkgs-unstable.llama-cpp-vulkan;
    host = "127.0.0.1";
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
