# KN-3012 checked updater

This is a dedicated updater for the audited KN-3012 / Linux 4.9-ndm-5 layout. It is not an upstream KeenKit release or an officially supported Keenetic tool.

The offline suite uses a simulated device. A live preflight is required before using the updater on a router.

## What it does

- Defaults to preflight only. Flashing requires an explicit `--apply` argument.
- Requires the router's root shell, a KN-3012 identity from the local API, and the audited kernel version.
- Requires automatic firmware updates to be disabled, settled dual-slot state, and working UBIFS internal storage.
- Resolves MTD devices by partition name and verifies exact offsets, sizes, erase sizes, NAND type, write flags, and device node identities. It refuses unfamiliar layouts.
- Requires an explicit trusted SHA-256 and checks the SDK image's board ID, uImage checksums, size, and legacy trailer checksum. It does not accept arbitrary vendor/ported firmware formats.
- Backs up both raw configuration partitions and the update plan/boot state into a private directory under /storage. The directory contains sensitive router configuration and must remain private.
- Writes only the inactive firmware slot. Closes/flushes the block writer, then verifies the image hash by reading the raw MTD character device.
- Detects active configuration changes, copies the verified configuration snapshot to the inactive configuration slot, and verifies that copy through raw MTD.
- Changes boot selection only after all previous checks pass. Reads the persistent U-State header back from raw MTD after committing it.
- Does not reboot automatically. If boot-state commit fails or cannot be verified, it reports uncertainty and instructs the operator not to reboot.

The active firmware is left intact. The old contents of the inactive firmware slot are replaced. No bootloader/EEPROM/U-Config partition is written. The U-State driver is used only at the final boot-selection stage.

## Prerequisites after the first TFTP installation

1. Confirm that the custom firmware booted and that `exec sh` provides a working root shell.
2. Initialize internal storage and Entware separately. This script does not create or format storage.
3. Install Python 3.9 or newer through Entware, with the standard-library modules used by this script. The interpreter is expected at `/opt/bin/python3`. Check imports before proceeding:

   ```sh
   /opt/bin/python3 -c 'import argparse, dataclasses, fcntl, hashlib, json, pathlib, platform, re, stat, struct, urllib.request, zlib'
   ```

   Entware Python package splits and installed size must be checked on the actual router. Keep enough room for the firmware image and at least 4 MiB additional free space. If the needed interpreter/modules do not fit, stop; do not remove safety checks to make the script run.
4. Disable automatic firmware updates in the router UI. Save the configuration that should survive the update. In the router admin CLI, the save command is `system configuration save`.
5. Keep a configuration and stock-firmware backup on another computer. Avoid changing router configuration or running any other updater during flashing.
6. Transfer `kn3012-update.py` and the intended KN-3012 firmware image onto the router. Keep the firmware under the UBIFS `/storage` mount. Obtain its expected SHA-256 from the trusted build's `SHA256SUMS` file on the computer.

## Live preflight (does not flash)

With your selected image transferred to `/storage/next.bin` and this script to `/storage/kn3012-update.py`, substitute the SHA-256 from that build’s checksum file.

```sh
/opt/bin/python3 /storage/kn3012-update.py /storage/next.bin \
  --sha256 <sha256>
```

The preflight prints the current/target slots and validation result. It may create a process lock file; it does not write flash or change boot selection.

If preflight fails, retain the output and investigate the cause. Never bypass model, geometry, state, storage, or checksum checks.

## Applying a future update

Only after a live preflight and a separately deliberate decision to flash, repeat the same command with `--apply` appended. It overwrites the inactive firmware/configuration slots and commits the next-boot selection. A successful run prints the backup directory and explicitly says to reboot manually. A failed run must not be treated as success.

If an error mentions an uncertain boot-state commit or says not to reboot, keep the router powered and inspect the boot state before taking further action. No live rollback procedure has been tested yet.

## Reproducing the offline checks

Run from the project directory:

```sh
./firmware.sh test-updater
./firmware.sh test-updater path/to/firmware.bin <sha256>
```

The tests use temporary regular files and mocked boot-state methods. They cover both slot directions, image validation, geometry and storage failures, unsettled boot state, write errors, corrupt readback, configuration changes, and boot-state commit failures.
