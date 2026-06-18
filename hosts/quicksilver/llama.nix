{
  config,
  lib,
  pkgs,
  ...
}: let
  user = "ilma4";
  userHome = config.users.users.${user}.home;
  host = "127.0.0.1";
  port = 8002;

  qwen36_35b_q8_modelName = "Qwen3.6-35B-A3B-UD-Q8_K_XL";
  qwen36_35b_q8_modelId = "unsloth/Qwen3.6-35B-A3B-q8";
  qwen36_35b_q8 = pkgs.fetchurl {
    name = "${qwen36_35b_q8_modelName}.gguf";
    url = "https://huggingface.co/unsloth/Qwen3.6-35B-A3B-GGUF/resolve/a483e9e6cbd595906af30beda3187c2663a1118c/${qwen36_35b_q8_modelName}.gguf";
    hash = "sha256-t2IhXF9Qf0hl30rD0a+oA4KK+kHgXsrD+sQxpnu9iOg=";
  };

  modelsPreset = pkgs.writeText "qwen36-models.ini" ''
    [*]
    ctx-size = 128000
    predict = 32768
    temp = 0.6
    top-p = 0.95
    top-k = 20
    min-p = 0.00
    presence-penalty = 0.0
    repeat-penalty = 1.0
    sleep-idle-seconds = 300
    parallel = 1
    n-gpu-layers = 99
    jinja = true
    chat-template-kwargs = {"preserve_thinking":true}
    load-on-startup = false

    [${qwen36_35b_q8_modelId}]
    model = ${qwen36_35b_q8}
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
        "${lib.getExe' pkgs.llama-cpp "llama-server"}"
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
