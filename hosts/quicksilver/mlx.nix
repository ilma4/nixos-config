{
  config,
  lib,
  pkgs,
  ...
}: let
  user = "ilma4";
  userHome = config.users.users.${user}.home;
  host = "127.0.0.1";
  port = 8001;

  # MLX 8-bit conversion of Qwen3.6-35B-A3B. mlx-openai-server downloads it from
  # the HuggingFace hub (into the HF cache under $HOME) the first time the model
  # is requested; nothing is pinned in the Nix store.
  modelId = "unsloth/Qwen3.6-35B-A3B-MLX-8bit";

  # Logs live in /var/log. A launchd *user* agent can't create files in the
  # root-owned directory itself, so they are pre-created by a root activation
  # script (see system.activationScripts.postActivation below).
  stdoutLog = "/var/log/mlx.log";
  stderrLog = "/var/log/mlx.err.log";

  # Authenticate to the HuggingFace hub when this token file is present. The
  # token is read at runtime so it never lands in the world-readable Nix store;
  # if the file is absent the server still runs (the model is public). HF_TOKEN
  # is the variable huggingface_hub (used to download the model) looks for.
  hfTokenFile = "${userHome}/NoBackup/hf-token";
  withHfToken = pkgs.writeShellScript "mlx-with-hf-token" ''
    set -euo pipefail
    if [ -r "${hfTokenFile}" ]; then
      HF_TOKEN="$(<"${hfTokenFile}")"
      export HF_TOKEN
    fi
    exec "$@"
  '';

  # mlx-openai-server only exposes on-demand idle unloading through its
  # config-file mode, so the server is driven by YAML rather than CLI flags.
  # on_demand = lazy-load the model on first request and unload it after the
  # idle timeout (replaces llama.cpp load-on-startup=false + sleep-idle=300).
  # Note: temperature/top-p/top-k are not config-file keys, so per-request
  # sampling is left to the client (model card: temp 0.6 / top-p 0.95 / top-k 20).
  # TODO: mlx-openai-server 1.8.1 rejects the OpenAI `developer` message role
  # (HTTP 422), so the pi client pins compat.supportsDeveloperRole = false in
  # ~/.pi/agent/models.json and sends `system` instead. Re-enable the developer
  # role there once a future mlx-openai-server version accepts it.
  serverConfig = (pkgs.formats.yaml {}).generate "mlx-openai-server.yaml" {
    server = {
      inherit host port;
      log_level = "INFO";
    };
    models = [
      {
        model_path = modelId;
        model_type = "lm";
        served_model_name = "qwen3.6-35b-a3b";
        context_length = 128000;
        default_max_tokens = 32768;
        on_demand = true;
        on_demand_idle_timeout = 300;
      }
    ];
  };
in {
  assertions = [
    {
      assertion = config.system.primaryUser == user;
      message = "mlx uses launchd.user.agents and must run as the ${user} primary user.";
    }
  ];

  # OpenAI-compatible MLX server (mlx-openai-server), installed and run via uv
  # (uvx) rather than nixpkgs. uv caches the tool environment and a managed
  # Python under $HOME, so HOME must be present in the agent environment. The
  # withHfToken shim injects HF_TOKEN (when available) before exec'ing uv.
  launchd.user.agents.mlx = {
    serviceConfig = {
      EnvironmentVariables = {
        HOME = userHome;
      };
      ProgramArguments = [
        "${withHfToken}"
        "${lib.getExe' pkgs.uv "uv"}"
        "tool"
        "run"
        # Pin Python 3.12. mlx-openai-server 1.8.1 requires >=3.11,<3.13, and
        # its transitive dep outlines-core 0.1.26 only ships wheels up to
        # cp312. Without this, uv picks Python 3.13 and falls back to building
        # outlines-core from source, which needs a Rust compiler that is not in
        # the agent's PATH (build_rust -> "can't find Rust compiler"). uv
        # auto-downloads a managed CPython 3.12 under $HOME on first run.
        "--python"
        "3.12"
        "--from"
        # Intentionally unpinned: keep resolving the latest mlx-openai-server
        # from PyPI on agent startup so local fixes and upstream compatibility
        # updates are picked up without editing this flake.
        "mlx-openai-server"
        "mlx-openai-server"
        "launch"
        "--config"
        "${serverConfig}"
      ];
      RunAtLoad = true;
      KeepAlive = true;
      WorkingDirectory = userHome;
      StandardOutPath = stdoutLog;
      StandardErrorPath = stderrLog;
    };
  };

  # The user agent above cannot create files in root-owned /var/log, so create
  # them here as root and hand ownership to ${user} so the agent can append.
  # This runs in extraActivation (not postActivation) because nix-darwin loads
  # launchd.user.agents during userLaunchd, which runs *before* postActivation;
  # extraActivation runs earlier still, so the files exist before the RunAtLoad
  # agent first starts.
  system.activationScripts.extraActivation.text = ''
    touch ${stdoutLog} ${stderrLog}
    chown ${user} ${stdoutLog} ${stderrLog}
  '';
}
