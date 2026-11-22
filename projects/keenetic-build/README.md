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

## Bump the KeeneticOS release

1. Find the stable release for the [KN-3012](https://osvault.keenetic.ru/KN-3012/) and note its exact build ID (for example, `5.1.10` is `5.01.C.10.0-0`). Check the [official SDK tags](https://github.com/keenetic/keenetic-sdk/tags) for that exact ID. **Stop if the tag is missing.** The stock firmware can be released before the matching SDK; changing the version metadata on an older SDK is not an upgrade. This is currently the blocker for `5.1.10`.
2. Once the tag is available, download the SDK tarball for the **commit** behind it (`https://codeload.github.com/keenetic/keenetic-sdk/tar.gz/<full-commit-sha>`). Obtain a stock KN-3012 export from the router’s system-file download and matching donor images from the [KN-1912](https://osvault.keenetic.ru/KN-1912/) and [KN-3810](https://osvault.keenetic.ru/KN-3810/) archives. Check that all three firmware inputs have the intended model and exact build ID. Run `sha256sum` on the four files and update their entries in `container/sources.tsv` with the new hashes, firmware filenames, and URLs. Keep the stock entry first and its URL set to `-`; put the stock export in your input directory under the name in the manifest. Keep the binaries out of the repository.
3. Update the references to the old release:
   - `container/build.sh`: stock filename and SDK metadata. Set `GIT_TAG` to the exact build ID, `version.date` to the SDK commit’s committer timestamp in Unix seconds, `BSP_CDATE` to that commit date in `DD Mon YYYY` form, and `BSP_EXACT` to `0-` followed by the short SDK commit SHA.
   - `firmware.sh`: stock filename. `container/customize-sdk.py`: donor filenames. `container/verify-image.py`: expected trailer version. `README.md`: release and example filename.
   - Remove the old `.work/cache/sdk.tar.gz` before building. The cache filename stays the same, so the old archive will fail the new checksum.
4. Run the build and both offline checks from this directory. Replace the example image path with the one printed by the build; take its checksum from that run’s `SHA256SUMS`.

   ```bash
   ./firmware.sh build "$HOME/keenetic-build/inputs"
   ./firmware.sh verify path/to/new-firmware.bin "$HOME/keenetic-build/inputs"
   ./firmware.sh test-updater path/to/new-firmware.bin 'SHA256_FROM_BUILD'
   ```

   If any check fails, investigate the change in the SDK or firmware rather than weakening the checks. A passing build does not flash the router or prove it will boot. Follow the [updater’s live preflight](updater/README.md#live-preflight-does-not-flash) separately before considering an on-router update.

## Router helpers

- [Updater](updater/README.md) covers the separate on-router update workflow and its preflight.
- [SSH transfer and service](ssh/README.md) documents reusing a local Dropbear or OpenSSH payload.
- [Entware hooks](entware/README.md) documents the package manifests, local bootstrap archive, and update schedule hook.
- [NAT66 hooks](nat66/README.md) documents applying forwarding rules for a configured LAN and uplink.

Firmware inputs, compiled payloads, output, and scratch data stay local. Keep device backups, private keys, and captures in the original workspace.
