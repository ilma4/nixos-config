#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
default_flake_location="$(cd -- "${script_dir}/.." && pwd -P)"
flake_location="${FLAKE_LOCATION:-${default_flake_location}}"

nix flake check --all-systems "path:${flake_location}"
