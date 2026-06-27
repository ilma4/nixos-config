{
  config,
  lib,
  pkgs,
  pkgs-unstable,
  ...
}: let
  user = "ilma4";
  userHome = config.users.users.${user}.home;
  host = "127.0.0.1";
  port = 8002;

  qwen36_27b_q4_modelName = "Qwen3.6-27B-UD-Q4_K_XL";
  qwen36_27b_q4_modelId = "unsloth/Qwen3.6-27B-q4";
  qwen36_27b_q4 = pkgs.fetchurl {
    name = "${qwen36_27b_q4_modelName}.gguf";
    url = "https://huggingface.co/unsloth/Qwen3.6-27B-GGUF/resolve/82d411acf4a06cfb8d9b073a5211bf410bfc29bf/${qwen36_27b_q4_modelName}.gguf";
    hash = "sha256-/2lB3tUls06xWUlnYsKd0Oxucdwxt01X512HGgPuwlk=";
  };

  modelsPreset = pkgs.writeText "qwen36-models.ini" ''
    [*]
    ctx-size = 262144
    predict = 32768
    temp = 0.6
    top-p = 0.95
    top-k = 20
    min-p = 0.00
    presence-penalty = 0.0
    repeat-penalty = 1.0
    sleep-idle-seconds = 900
    parallel = 1
    n-gpu-layers = 99
    jinja = true
    chat-template-kwargs = {"preserve_thinking":true}
    load-on-startup = false

    [${qwen36_27b_q4_modelId}]
    model = ${qwen36_27b_q4}
  '';
in {
  assertions = [
    {
      assertion = config.system.primaryUser == user;
      message = "llama-cpp uses launchd.user.agents and must run as the ${user} primary user.";
    }
  ];

  launchd.user.agents.llama-cpp = {
    serviceConfig = {
      EnvironmentVariables = {
        HOME = userHome;
      };
      ProgramArguments = [
        "${lib.getExe' pkgs-unstable.llama-cpp "llama-server"}"
        "--models-preset"
        "${modelsPreset}"
        "--models-max"
        "1"
        "--models-autoload"
        "--host"
        host
        "--port"
        (toString port)
        "--no-ui"
      ];
      RunAtLoad = true;
      KeepAlive = true;
      WorkingDirectory = userHome;
      StandardOutPath = "${userHome}/Library/Logs/llama-cpp.log";
      StandardErrorPath = "${userHome}/Library/Logs/llama-cpp.err.log";
    };
  };
}
