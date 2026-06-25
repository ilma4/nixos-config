{
  lib,
  pkgs,
  ...
}: let
  oldMlxLmModelId = "unsloth/Qwen3.6-35B-A3B-MLX-8bit";
  omlxModelId = "unsloth--Qwen3.6-35B-A3B-MLX-8bit";
in {
  home.file.".pi/agent/models.json".source = ./pi/models.json;
  home.file.".pi/agent/extensions/notify-finish.ts".source = ./pi/extensions/notify-finish.ts;

  # oMLX exposes HuggingFace cache-backed models with a route-safe id where
  # slashes are encoded as "--". Migrate Pi's mutable settings file so an old
  # default/enabled model does not keep sending the mlx-lm/HuggingFace id.
  home.activation.migratePiOmlxModelId = lib.hm.dag.entryAfter ["writeBoundary"] ''
    set -euo pipefail

    settings_path="$HOME/.pi/agent/settings.json"
    if [ -e "$settings_path" ]; then
      if [ -n "''${DRY_RUN_CMD:-}" ]; then
        echo "Would migrate Pi oMLX model id in $settings_path"
      else
        ${lib.getExe pkgs.python3} - \
          "$settings_path" \
          ${lib.escapeShellArg oldMlxLmModelId} \
          ${lib.escapeShellArg omlxModelId} <<'PY'
import json
import sys
from pathlib import Path

settings_path = Path(sys.argv[1])
old_model_id = sys.argv[2]
omlx_model_id = sys.argv[3]

with settings_path.open(encoding="utf-8") as f:
    data = json.load(f)

if not isinstance(data, dict):
    raise SystemExit(f"{settings_path} must contain a JSON object")

changed = False

if data.get("defaultProvider") == "mlx":
    data["defaultProvider"] = "omlx"
    changed = True

if data.get("defaultModel") == old_model_id:
    data["defaultModel"] = omlx_model_id
    changed = True

old_provider_model_ids = {
    f"mlx/{old_model_id}",
    f"omlx/{old_model_id}",
    f"mlx/{omlx_model_id}",
}
omlx_provider_model_id = f"omlx/{omlx_model_id}"

enabled_models = data.get("enabledModels")
if isinstance(enabled_models, list):
    migrated = []
    for model in enabled_models:
        if model in old_provider_model_ids:
            model = omlx_provider_model_id
        if model not in migrated:
            migrated.append(model)
    if migrated != enabled_models:
        data["enabledModels"] = migrated
        changed = True

if changed:
    tmp_path = settings_path.with_suffix(settings_path.suffix + ".tmp")
    with tmp_path.open("w", encoding="utf-8") as f:
        json.dump(data, f, indent=2, ensure_ascii=False)
        f.write("\n")
    tmp_path.replace(settings_path)
PY
      fi
    fi
  '';
}
