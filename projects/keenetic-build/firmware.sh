#!/usr/bin/env bash
set -euo pipefail

usage() {
    printf '%s\n' 'Usage: firmware.sh build [input-dir]' \
        '       firmware.sh verify <image> [input-dir]' \
        '       firmware.sh test-updater [<image> <sha256>]'
}

project=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
action=${1:-}
case "$action" in
    build) (( $# <= 2 )) || { usage >&2; exit 2; }; input_dir=${2:-$project/inputs} ;;
    verify) (( $# >= 2 && $# <= 3 )) || { usage >&2; exit 2; }; input_dir=${3:-$project/inputs} ;;
    test-updater) (( $# == 1 || $# == 3 )) || { usage >&2; exit 2; } ;;
    -h|--help) usage; exit 0 ;;
    *) usage >&2; exit 2 ;;
esac

if [[ -n "${input_dir:-}" ]]; then
    stock=KN-3012-5.01.C.8.0-2-stock.bin
    if [[ ! -f "$input_dir/$stock" ]]; then
        printf 'Missing stock firmware: %s/%s\n' "$input_dir" "$stock" >&2
        exit 1
    fi
    input_dir=$(realpath -- "$input_dir")
fi
if [[ "$action" == verify || "$action" == test-updater && $# == 3 ]]; then
    if [[ ! -f "$2" ]]; then
        printf 'Firmware image does not exist: %s\n' "$2" >&2
        exit 1
    fi
    image=$(realpath -- "$2")
    image_mount="/image/${image##*/}"
fi
if [[ -n "${JOBS:-}" && ! "$JOBS" =~ ^[1-9][0-9]*$ ]]; then
    printf 'JOBS must be a positive integer\n' >&2
    exit 2
fi

mkdir -p "$project/.work"
invocation=$(mktemp -d "$project/.work/invocation.XXXXXXXX")
staging=
cleanup() {
    rm -rf -- "$invocation"
    if [[ -n "$staging" ]]; then
        rm -rf -- "$staging"
    fi
}
trap cleanup EXIT

build_container() {
    podman build --iidfile "$invocation/image-id" "$project/container"
}

run_container() {
    podman run --rm --userns=keep-id:uid=10001,gid=10001 "$@"
}

case "$action" in
    build)
        mkdir -p "$project/output" "$project/logs"
        staging=$(mktemp -d "$project/output/.build.XXXXXXXX")
        run_id=${staging##*/.}
        log="$project/logs/$run_id.log"
        printf 'Build log: %s\n' "$log"
        build_container 2>&1 | tee "$log"
        run_container --env "JOBS=${JOBS:-}" --volume "$input_dir:/inputs:ro" \
            --volume "$project/.work:/work:rw" --volume "$staging:/output:rw" \
            "$(cat "$invocation/image-id")" bash /opt/keenetic/build.sh 2>&1 | tee -a "$log"
        mv -T -- "$staging" "$project/output/$run_id"
        staging=
        printf 'Firmware output: %s\n' "$project/output/$run_id"
        ;;
    verify)
        build_container
        run_container --network=none --volume "$input_dir:/inputs:ro" \
            --volume "$image:$image_mount:ro" "$(cat "$invocation/image-id")" \
            bash /opt/keenetic/build.sh verify "$image_mount"
        ;;
    test-updater)
        build_container
        mounts=(--volume "$project/updater:/updater:ro")
        args=()
        if (( $# == 3 )); then
            mounts+=(--volume "$image:$image_mount:ro")
            args=("$image_mount" "$3")
        fi
        run_container --network=none "${mounts[@]}" "$(cat "$invocation/image-id")" \
            python3 /updater/test_updater.py "${args[@]}"
        ;;
esac
