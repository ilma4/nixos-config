{
  config,
  lib,
  pkgs,
  ...
}: let
  user = "ilma4";
  userHome = config.users.users.${user}.home;
  host = "127.0.0.1";
  port = 8003;
  launchdLabel = "org.nixos.mlx";
  launchdPlist = "${userHome}/Library/LaunchAgents/${launchdLabel}.plist";

  # MLX 8-bit conversion of Qwen3.6-35B-A3B. mlx-lm downloads it from the
  # HuggingFace hub (into the HF cache under $HOME) the first time the model is
  # requested; nothing is pinned in the Nix store.
  modelId = "unsloth/Qwen3.6-35B-A3B-MLX-8bit";

  # Logs live in /tmp, which is world-writable (sticky bit), so this launchd
  # *user* agent creates them itself on spawn (launchd opens StandardOutPath /
  # StandardErrorPath with O_CREAT). Root-owned /var/log instead required a
  # root activation script to pre-create and chown the files; that chown raced
  # the agent's RunAtLoad spawn during a darwin switch and intermittently left
  # launchd unable to open the log paths, failing the spawn with EX_CONFIG (78)
  # until the job was throttled into launchd's "penalty box" and stopped
  # restarting (leaving the server down). /tmp removes that whole class of race.
  stdoutLog = "/tmp/mlx.log";
  stderrLog = "/tmp/mlx.err.log";

  # Authenticate to the HuggingFace hub when this token file is present. The
  # token is read at runtime so it never lands in the world-readable Nix store;
  # if the file is absent the server still runs (the model is public). HF_TOKEN
  # is the variable huggingface_hub (used to download the model) looks for.
  hfTokenFile = "${userHome}/NoBackup/hf-token";
  # Launch wrapper for the agent: inject HF_TOKEN when available (see above),
  # then exec the server via uv. uv installs mlx-lm plus its runtime
  # deps (mlx, transformers, ...) into a tool env cached under $HOME, so HOME
  # must be set in the agent environment. --python 3.12 pins an interpreter with
  # prebuilt mlx/transformers wheels; unpinned, uv may pick a newer CPython
  # lacking an mlx wheel and try to build mlx (native) from source. Server flags
  # are appended by ProgramArguments and arrive via "$@".
  mlxLaunch = pkgs.writeShellScript "mlx-launch" ''
    set -euo pipefail
    if [ -r "${hfTokenFile}" ]; then
      HF_TOKEN="$(<"${hfTokenFile}")"
      export HF_TOKEN
    fi
    exec ${lib.getExe' pkgs.uv "uv"} tool run \
      --python 3.12 \
      --from mlx-lm \
      mlx_lm.server "$@"
  '';

  mkMlxControlScript = name: action:
    pkgs.writeShellScriptBin name ''
      set -euo pipefail

      launchd_user=${lib.escapeShellArg user}
      launchd_label=${lib.escapeShellArg launchdLabel}
      launchd_plist=${lib.escapeShellArg launchdPlist}

      if [ "$(/usr/bin/id -un)" != "$launchd_user" ] && [ "$(/usr/bin/id -u)" -ne 0 ]; then
        exec /usr/bin/sudo -n /run/current-system/sw/bin/${name} "$@"
      fi

      launchd_uid="$(/usr/bin/id -u "$launchd_user")"

      if [ ! -f "$launchd_plist" ]; then
        echo "MLX LaunchAgent plist not found: $launchd_plist" >&2
        exit 1
      fi

      run_launchctl() {
        if [ "$(/usr/bin/id -un)" = "$launchd_user" ]; then
          /bin/launchctl "$@"
        else
          /bin/launchctl asuser "$launchd_uid" /usr/bin/sudo --user="$launchd_user" -- /bin/launchctl "$@"
        fi
      }

      ${action}
    '';
  startMlx = mkMlxControlScript "start-mlx" ''
    if ! run_launchctl print "gui/$launchd_uid/$launchd_label" >/dev/null 2>&1; then
      run_launchctl load -w "$launchd_plist"
    fi
    run_launchctl kickstart -k "gui/$launchd_uid/$launchd_label"
  '';
  stopMlx = mkMlxControlScript "stop-mlx" ''
    if run_launchctl print "gui/$launchd_uid/$launchd_label" >/dev/null 2>&1; then
      run_launchctl unload -w "$launchd_plist"
    fi
  '';

  # mlx-lm is configured entirely through CLI flags (no YAML config file).
  #
  # Reasoning and tool calls need NO parser flags here: mlx-lm auto-detects both
  # from the model itself, where mlx-openai-server required explicit
  # reasoning_parser/tool_call_parser keys.
  #   * Reasoning: Qwen3.6 has <think>/</think> in its vocab, so mlx-lm runs a
  #     token-level state machine that splits the chain-of-thought into the
  #     response's `message.reasoning` field, leaving `content` clean. (Field
  #     name is `reasoning`, not mlx-openai-server's `reasoning_content` — the
  #     pi client may need to read the new key.)
  #   * Tool calls: the chat template emits the XML "<tool_call>\n<function=..."
  #     format, which mlx-lm's _infer_tool_parser maps to the qwen3_coder tool
  #     parser automatically (the same parser the old config named by hand).
  #
  # --max-tokens 32768 replaces default_max_tokens (mlx-lm's own default is 512)
  # and caps generation when a client omits max_tokens.
  #
  # Dropped vs the old YAML, with no mlx-lm equivalent and no behaviour loss:
  #   * context_length: governed by the model's own config; mlx-lm has no flag.
  #   * served_model_name: mlx-lm reports/accepts the model by its repo id. The
  #     old "qwen3.6-35b-a3b" alias no longer resolves, so clients must send
  #     `model: "${modelId}"` or omit `model` (which uses the loaded default).
  #
  # Sampling defaults follow the Qwen3 model card (temp 0.6 / top-p 0.95 /
  # top-k 20). mlx-lm's --temp/--top-p/--top-k set the server-side defaults used
  # whenever a client omits its own sampling (a client that sends explicit
  # values still overrides them). These were previously injected client-side by
  # a pi extension (pi/extensions/lmstudio-inference-params.ts); setting them on
  # the server makes that extension redundant and applies to every client. mlx-lm
  # otherwise defaults to --temp 0.0 (greedy), which Qwen3 warns against. min-p
  # and the presence/repetition penalties already default to no-op in mlx-lm,
  # matching the model card, so they need no flags.
  #
  # The OpenAI `developer` message role now works: mlx-lm forwards roles
  # straight to apply_chat_template (no HTTP 422 like mlx-openai-server 1.8.1),
  # and this model's chat template handles `developer` (treated as `system`). So
  # the pi client can re-enable compat.supportsDeveloperRole in
  # ~/.pi/agent/models.json.
  serverArgs = [
    "--model"
    modelId
    "--host"
    host
    "--port"
    (toString port)
    "--log-level"
    "INFO"
    "--max-tokens"
    "32768"
    "--temp"
    "0.6"
    "--top-p"
    "0.95"
    "--top-k"
    "20"
  ];
in {
  assertions = [
    {
      assertion = config.system.primaryUser == user;
      message = "mlx uses launchd.user.agents and must run as the ${user} primary user.";
    }
  ];

  # OpenAI-compatible MLX server (mlx-lm's mlx_lm.server), run via uv (uvx)
  # rather than nixpkgs. mlxLaunch handles the HF token and uv invocation; the
  # agent just appends the server flags. uv caches its tool environment and a
  # managed Python under $HOME, so HOME must be present in the agent environment.
  launchd.user.agents.mlx = {
    serviceConfig = {
      EnvironmentVariables = {
        HOME = userHome;
      };
      Label = launchdLabel;
      ProgramArguments = ["${mlxLaunch}"] ++ serverArgs;
      RunAtLoad = true;
      KeepAlive = true;
      WorkingDirectory = userHome;
      StandardOutPath = stdoutLog;
      StandardErrorPath = stderrLog;
    };
  };

  environment.systemPackages = [
    startMlx
    stopMlx
  ];

  security.sudo.extraConfig = ''
    malakhov ALL=(root) NOPASSWD: /run/current-system/sw/bin/start-mlx, /run/current-system/sw/bin/stop-mlx
  '';
}
