{
  config,
  lib,
  pkgs,
  ...
}: let
  homebrewPrefix =
    config.homebrew.prefix or (lib.removeSuffix "/bin" config.homebrew.brewPrefix);

  user = "ilma4";
  userHome = config.users.users.${user}.home;
  host = "127.0.0.1";
  port = 8003;
  launchdLabel = "org.nixos.mlx";
  launchdPlist = "${userHome}/Library/LaunchAgents/${launchdLabel}.plist";

  # oMLX discovers local MLX model directories under ~/.omlx/models and, by
  # default, compatible MLX snapshots in the standard HuggingFace cache. Keep
  # the old HuggingFace repo id as an oMLX model alias so existing clients do
  # not need to change their configured model name.
  modelDir = "${userHome}/.omlx/models";
  modelId = "unsloth/Qwen3.6-35B-A3B-MLX-8bit";
  hfCacheModelId = "unsloth--Qwen3.6-35B-A3B-MLX-8bit";

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
  # then exec the Homebrew-installed oMLX server. Server flags are appended by
  # ProgramArguments and arrive via "$@".
  omlxLaunch = pkgs.writeShellScript "omlx-launch" ''
    set -euo pipefail
    if [ -r "${hfTokenFile}" ]; then
      HF_TOKEN="$(<"${hfTokenFile}")"
      export HF_TOKEN
    fi
    exec "${homebrewPrefix}/bin/omlx" serve "$@"
  '';

  omlxModelSettings = pkgs.writeShellScript "omlx-model-settings" ''
    set -euo pipefail

    settings_dir=${lib.escapeShellArg "${userHome}/.omlx"}
    settings_path="$settings_dir/model_settings.json"

    /usr/bin/install -d -m 0700 -o ${lib.escapeShellArg user} -g staff "$settings_dir"

    ${lib.getExe pkgs.python3} - \
      "$settings_path" \
      ${lib.escapeShellArg hfCacheModelId} \
      ${lib.escapeShellArg modelId} <<'PY'
import json
import sys
from pathlib import Path

settings_path = Path(sys.argv[1])
hf_cache_model_id = sys.argv[2]
model_alias = sys.argv[3]

if settings_path.exists():
    with settings_path.open(encoding="utf-8") as f:
        data = json.load(f)
else:
    data = {}

if not isinstance(data, dict):
    raise SystemExit(f"{settings_path} must contain a JSON object")

data.setdefault("version", 1)
models = data.setdefault("models", {})
if not isinstance(models, dict):
    raise SystemExit(f"{settings_path}: 'models' must be a JSON object")

model = models.setdefault(hf_cache_model_id, {})
if not isinstance(model, dict):
    raise SystemExit(
        f"{settings_path}: settings for {hf_cache_model_id!r} must be a JSON object"
    )

model.update(
    {
        "model_alias": model_alias,
        "max_context_window": 262144,
        "max_tokens": 32768,
        "temperature": 0.6,
        "top_p": 0.95,
        "top_k": 20,
    }
)

tmp_path = settings_path.with_suffix(settings_path.suffix + ".tmp")
with tmp_path.open("w", encoding="utf-8") as f:
    json.dump(data, f, indent=2, ensure_ascii=False)
    f.write("\n")
tmp_path.replace(settings_path)
PY

    /usr/sbin/chown ${lib.escapeShellArg user}:staff "$settings_path"
    /bin/chmod 0600 "$settings_path"
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
        echo "oMLX LaunchAgent plist not found: $launchd_plist" >&2
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

  # oMLX is a multi-model OpenAI/Anthropic-compatible server. It discovers MLX
  # model directories rather than taking one --model argument. Server bind
  # options stay in launchd; per-model alias/sampling defaults are kept in
  # ~/.omlx/model_settings.json by omlxModelSettings below.
  serverArgs = [
    "--model-dir"
    modelDir
    "--host"
    host
    "--port"
    (toString port)
    "--log-level"
    "info"
  ];
in {
  assertions = [
    {
      assertion = config.system.primaryUser == user;
      message = "oMLX uses launchd.user.agents and must run as the ${user} primary user.";
    }
  ];

  homebrew = {
    taps = [
      {
        name = "jundot/omlx";
        clone_target = "https://github.com/jundot/omlx";
        trusted = true;
      }
    ];
    brews = [
      "jundot/omlx/omlx"
    ];
  };

  system.activationScripts.postActivation.text = lib.mkAfter ''
    set -euo pipefail
    ${omlxModelSettings}
  '';

  # OpenAI/Anthropic-compatible oMLX server, installed by Homebrew and launched
  # by nix-darwin so it keeps the existing start-mlx/stop-mlx controls and port.
  # HOME must be present so oMLX uses the user's ~/.omlx and HF cache.
  launchd.user.agents.mlx = {
    serviceConfig = {
      EnvironmentVariables = {
        HOME = userHome;
      };
      Label = launchdLabel;
      ProgramArguments = ["${omlxLaunch}"] ++ serverArgs;
      # Keep oMLX stopped by default; use start-mlx to launch it manually.
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
