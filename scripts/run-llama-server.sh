#!/usr/bin/env bash
set -euo pipefail

# Starts a llama.cpp router server that serves every .gguf model in
# MODELS_DIR on 127.0.0.1:7777 (OpenAI-compatible API).
#
# Usage: run-llama-server.sh MODELS_DIR [extra llama-server args...]
#
# The model used is selected by the client via the OpenAI API `model`
# field (or by pi selecting the llama.cpp/<model> model).

usage() {
    echo "usage: $(basename "$0") MODELS_DIR [extra llama-server args...]" >&2
    exit 1
}

[[ $# -ge 1 ]] || usage

models_dir="$1"
shift

[[ -d "$models_dir" ]] || {
    echo "error: models directory not found: $models_dir" >&2
    exit 1
}

command -v llama-server >/dev/null 2>&1 || {
    echo "error: llama-server not found in PATH" >&2
    exit 127
}

exec llama-server \
    --models-dir "$models_dir" \
    --host 127.0.0.1 \
    --port 7777 \
    --no-ui \
    --sleep-idle-seconds 900 \
    --temp 1.0 \
    --top-p 0.95 \
    --top-k 20 \
    --min-p 0.0 \
    "$@"
