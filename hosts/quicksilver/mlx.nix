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

  # MLX 8-bit conversion of Qwen3.6-35B-A3B. mlx-lm downloads it from the
  # HuggingFace hub (into the HF cache under $HOME) the first time the model is
  # requested; nothing is pinned in the Nix store.
  modelId = "unsloth/Qwen3.6-35B-A3B-MLX-8bit";

  # mlx-lm's HTTP server (`mlx_lm.server`), built from current upstream master
  # with ml-explore/mlx-lm#1274 ("feat: add --idle-timeout to unload model after
  # inactivity") applied on top. That PR is still open and its --idle-timeout is
  # the mlx-lm equivalent of the on-demand idle unloading this host relied on
  # before, so we carry just the patch until it lands in a release.
  #
  # We patch master rather than install the PR's fork branch because that branch
  # trails upstream (it was ~12 commits / about a month behind at the time of
  # writing) and would pin a stale mlx-lm. `rev` is the upstream main commit this
  # was last bumped to; the patch is fetched from the PR and re-applied against
  # that tree at build time (the test-only hunks are dropped — they are not
  # needed to run the server and only add conflict surface on future bumps). To
  # move forward, bump `rev`/`hash` to a newer master and refresh the patch
  # `hash`. When #1274 ships in a released mlx-lm, drop all of this and use the
  # plain `mlx-lm` package as the uv `--from`.
  mlxLmSrc = pkgs.applyPatches {
    name = "mlx-lm-master-pr1274";
    src = pkgs.fetchFromGitHub {
      owner = "ml-explore";
      repo = "mlx-lm";
      rev = "2c008fd0252b2c569227d12568356ab88ab0560a";
      hash = "sha256-K6gQrfMFNWPv84TI9q4sXOp0MOgSiMS7Im5EYWhgppY=";
    };
    patches = [
      (pkgs.fetchpatch {
        name = "idle-timeout-pr1274.patch";
        url = "https://github.com/ml-explore/mlx-lm/pull/1274.patch";
        excludes = ["tests/test_idle_unload.py" "tests/test_server.py"];
        hash = "sha256-8wtc1CMneV8yUzUwjBf8yEAmCPUN1U3H9x+AQ1su4UM=";
      })
    ];
  };

  # uv builds a *directory* `--from` source in-tree (setuptools writes
  # mlx_lm.egg-info next to setup.py), which fails on the read-only Nix store
  # path with "could not create 'mlx_lm.egg-info': Permission denied". So build
  # the wheel here — in a writable sandbox, offline, with nixpkgs setuptools —
  # and hand uv the finished wheel instead; uv then only resolves the runtime
  # deps (mlx, transformers, ...) from PyPI and never builds in-tree.
  mlxLmWheel = pkgs.stdenvNoCC.mkDerivation {
    name = "mlx-lm-master-pr1274-wheel";
    dontUnpack = true;
    nativeBuildInputs = [
      (pkgs.python312.withPackages (ps: with ps; [build setuptools wheel]))
    ];
    buildPhase = ''
      runHook preBuild
      cp -r ${mlxLmSrc} src
      chmod -R u+w src
      (cd src && python -m build --wheel --no-isolation --outdir dist)
      runHook postBuild
    '';
    installPhase = ''
      runHook preInstall
      mkdir -p "$out"
      cp src/dist/*.whl "$out"/
      runHook postInstall
    '';
  };

  # Logs live in /var/log. A launchd *user* agent can't create files in the
  # root-owned directory itself, so they are pre-created by a root activation
  # script (see system.activationScripts.extraActivation below).
  stdoutLog = "/var/log/mlx.log";
  stderrLog = "/var/log/mlx.err.log";

  # Authenticate to the HuggingFace hub when this token file is present. The
  # token is read at runtime so it never lands in the world-readable Nix store;
  # if the file is absent the server still runs (the model is public). HF_TOKEN
  # is the variable huggingface_hub (used to download the model) looks for.
  hfTokenFile = "${userHome}/NoBackup/hf-token";
  # Launch wrapper for the agent: inject HF_TOKEN when available (see above),
  # then exec the server via uv. uv installs the prebuilt wheel plus its runtime
  # deps (mlx, transformers, ...) into a tool env cached under $HOME, so HOME
  # must be set in the agent environment. The wheel filename carries the
  # version, so glob it rather than hardcode. --python 3.12 pins an interpreter
  # with prebuilt mlx/transformers wheels; unpinned, uv may pick a newer CPython
  # lacking an mlx wheel and try to build mlx (native) from source. Server flags
  # are appended by ProgramArguments and arrive via "$@".
  mlxLaunch = pkgs.writeShellScript "mlx-launch" ''
    set -euo pipefail
    if [ -r "${hfTokenFile}" ]; then
      HF_TOKEN="$(<"${hfTokenFile}")"
      export HF_TOKEN
    fi
    wheel="$(echo ${mlxLmWheel}/*.whl)"
    exec ${lib.getExe' pkgs.uv "uv"} tool run \
      --python 3.12 \
      --from "$wheel" \
      mlx_lm.server "$@"
  '';

  # mlx-lm is configured entirely through CLI flags (no YAML config file).
  #
  # --idle-timeout 300 (from PR #1274) unloads the model weights after 300s
  # without requests and reloads transparently on the next request, replacing
  # mlx-openai-server's on_demand + on_demand_idle_timeout. Note the lifecycle
  # differs slightly: mlx-lm loads the model eagerly at startup (the generation
  # thread calls load_default()), then unloads once idle; the old on_demand
  # deferred the *first* load until the first request. Steady-state behaviour
  # (idle -> unloaded -> reload on demand) is the same.
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
    "--idle-timeout"
    "300"
  ];
in {
  assertions = [
    {
      assertion = config.system.primaryUser == user;
      message = "mlx uses launchd.user.agents and must run as the ${user} primary user.";
    }
  ];

  # OpenAI-compatible MLX server (mlx-lm's mlx_lm.server), run via uv (uvx)
  # rather than nixpkgs. mlxLaunch handles the HF token, the prebuilt wheel and
  # the uv invocation; the agent just appends the server flags. uv caches its
  # tool environment and a managed Python under $HOME, so HOME must be present
  # in the agent environment.
  launchd.user.agents.mlx = {
    serviceConfig = {
      EnvironmentVariables = {
        HOME = userHome;
      };
      ProgramArguments = ["${mlxLaunch}"] ++ serverArgs;
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
