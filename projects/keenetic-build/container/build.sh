#!/usr/bin/env bash
set -euo pipefail

scripts=/opt/keenetic
check_hash() {
    if ! printf '%s  %s\n' "$1" "$2" | sha256sum --check --status; then
        printf 'Checksum mismatch for %s\n' "$2" >&2
        return 1
    fi
}

stock=/inputs/KN-3012-5.01.C.8.0-2-stock.bin
read -r stock_sha _ < "$scripts/sources.tsv"
if [[ ! -f "$stock" ]]; then
    printf 'Missing stock firmware: %s\n' "${stock##*/}" >&2
    exit 1
fi
check_hash "$stock_sha" "$stock"

if [[ "${1:-build}" == verify ]]; then
    exec python3 "$scripts/verify-image.py" "$2" "$stock"
fi

mkdir -p /work/cache /work/dl
exec 9>/work/build.lock
flock 9
run_dir=$(mktemp -d /work/build.XXXXXXXX)
trap 'chmod -R u+rwX "$run_dir"; rm -rf -- "$run_dir"' EXIT
mkdir "$run_dir/inputs" "$run_dir/sdk"

while read -r sha name url; do
    if [[ "$url" == - ]]; then
        source_file=$stock
    elif [[ "$name" == *-donor.bin && -f "/inputs/$name" ]]; then
        source_file=/inputs/$name
        check_hash "$sha" "$source_file"
    else
        source_file=/work/cache/$name
        if [[ ! -f "$source_file" ]]; then
            curl --fail --show-error --location --retry 3 --connect-timeout 20 \
                --output "$run_dir/download" "$url"
            check_hash "$sha" "$run_dir/download"
            mv "$run_dir/download" "$source_file"
        fi
        check_hash "$sha" "$source_file"
    fi
    ln -s "$source_file" "$run_dir/inputs/$name"
done < "$scripts/sources.tsv"

cp -L "$run_dir"/inputs/gnulib-*.tar.gz /work/dl/
export NDWRT_DL_PATH=/work/dl
export DOWNLOAD_MIRROR=https://sources.cdn.openwrt.org
export CURL_OPTIONS="--max-time 90 --retry 1"
jobs=${JOBS:-$(nproc)}
if [[ -z "${JOBS:-}" ]] && (( jobs > 12 )); then
    jobs=12
fi
export JOBS=$jobs

cd "$run_dir/sdk"
tar -xzf ../inputs/sdk.tar.gz --strip-components=1
printf '1792440349\n' > version.date
# Supply the release metadata that the SDK normally reads from a Git checkout.
sed -i '1,/^BSP_EPOCH/{ /^BSP_EPOCH/!d; }' include/release.mk
sed -i '1i GIT_TAG := 5.01.C.8.0-2\nBSP_CDATE := 19 Oct 2026\nBSP_LOCAL := none' include/release.mk
sed -i 's/^  BSP_EXACT := .*git log.*/  BSP_EXACT := 0-5c74fc4/' include/release.mk
sed -i '/^NCPU=/c\NCPU=$JOBS' unpack.sh
./unpack.sh -v "$stock"
python3 "$scripts/customize-sdk.py" "$PWD" "$run_dir/inputs"
rm -f tmp/info/.targetinfo-en7528 tmp/.targetinfo tmp/.config-target.in
make defconfig
for setting in TARGET_en7528_KN_3012 USES_EXTENDED_STORAGE PACKAGE_ndm-mod-shell \
    PACKAGE_ndm-mod-opkg PACKAGE_ndm-mod-storage-mtd PACKAGE_kmod-ndm-storage \
    PACKAGE_kmod-fs-ubi PACKAGE_kmod-fs-ubifs; do
    grep -qx "CONFIG_${setting}=y" .config
done
make -j"$jobs" V=s
shopt -s nullglob
images=(bin/en7528/*Firmware-KN-3012*.bin)
if (( ${#images[@]} != 1 )); then
    printf 'Expected one KN-3012 firmware image, found %s\n' "${#images[@]}" >&2
    exit 1
fi
cp .config /output/build.config
cp "${images[0]}" /output/
python3 "$scripts/verify-image.py" "/output/${images[0]##*/}" "$stock" --output /output
