# KeeneticOS for the KN-3012

This project builds KeeneticOS `5.01.C.8.0-2` for the Keenetic Speedster KN-3012. It retains the stock board identity and adds the admin CLI’s `exec sh` root shell, OPKG integration, and internal UBIFS storage support.

## Build on Linux

Use a working rootless Podman installation. The build runs in an Ubuntu 24.04 container and cross-compiles for MIPS. Allow several gigabytes of disk space for the SDK, toolchain, download cache, and container layers.

```bash
cd projects/keenetic-build
./firmware.sh build "$HOME/keenetic-build/inputs"
```

For a fresh checkout, place your export of stock `5.01.C.8.0-2` at `inputs/KN-3012-5.01.C.8.0-2-stock.bin` and run `./firmware.sh build`. The stock export comes from the router’s system-file download. The builder verifies it against the expected SHA-256. The matching KN-1912 and KN-3810 donor files are downloaded from Keenetic if absent. The pinned SDK and verified source downloads are cached under `.work/`. Set `JOBS=4` before the command to reduce parallelism.

Each successful run publishes the image, `build.config`, `SHA256SUMS`, and `validation.json` under `output/<run-id>/`. Build logs are in `logs/`. The SDK generates timestamped image names, so use the checksum from the selected run when identifying a firmware file.

## Offline checks

```bash
./firmware.sh verify path/to/firmware.bin "$HOME/keenetic-build/inputs"
./firmware.sh test-updater
./firmware.sh test-updater path/to/firmware.bin <sha256>
```

The verifier checks the image identity and checksums, extracts and checks the filesystem, compares the proprietary core library against the stock export, and executes BusyBox and ip6tables under QEMU. These checks cover the file and its userspace components. First boot, OPKG initialization, and root access on physical hardware require separate validation. The SDK output uses the legacy image trailer.

## Router helpers

- [Updater](updater/README.md) covers the separate on-router update workflow and its preflight.
- [SSH transfer and service](ssh/README.md) documents reusing a local Dropbear or OpenSSH payload.
- [Entware hooks](entware/README.md) documents the package manifests, local bootstrap archive, and update schedule hook.
- [NAT66 hooks](nat66/README.md) documents applying forwarding rules for a configured LAN and uplink.

Firmware inputs, compiled payloads, output, and scratch data stay local. Keep device backups, private keys, and captures in the original workspace.
