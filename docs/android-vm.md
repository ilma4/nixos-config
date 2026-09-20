# Android development VM

The `android-vm` NixOS configuration runs as an ARM64 Lima guest. Lima is
installed on the macOS host through Home Manager (`hosts/quicksilver/ilma4-home.nix`).
The guest also uses Home Manager for the `ilma4` user and enables the shared
development environment from `home/dev.nix`; Nix, Rust, zsh autoenv, and
direnv extras are disabled. Android builds run directly in the guest.

## Host setup

The Android VM uses a separate Lima home on the external volume. Mount the
volume at `/Volumes/Android` before running any Lima command. The quicksilver
Home Manager configuration sets `LIMA_HOME` to `/Volumes/Android/android-lima`
for the `ilma4` user, so use `limactl` for every command below. Mixing it with
the default Lima home makes the VM appear to be missing because Lima will look
in `~/.lima` instead.

`limactl` is installed by the quicksilver Home Manager configuration. While
bootstrapping that configuration, use
`LIMA_HOME=/Volumes/Android/android-lima limactl`.

### Recover an unavailable VM

Check the instance and confirm that the external volume is mounted:

```bash
test -d /Volumes/Android/android-lima
limactl list
```

If the instance is stopped, start the existing instance rather than creating a
new one:

```bash
limactl start android
```

Lima can show the instance as `Running` while the guest network or SSH server
is no longer reachable. If `shell` reports `Connection reset by peer`, `no
route to host`, or hangs, restart the instance and request a fresh SSH
connection:

```bash
limactl restart android
limactl shell --reconnect android
```

If restart does not recover it, do a full stop/start without deleting the
instance or its disk:

```bash
limactl stop android
limactl start android
```

### Move an existing VM to the external volume

Run this only when the VM still lives under Lima's default `~/.lima` home. The
backup is kept until the external copy has been started successfully.

```bash
set -euo pipefail

default_lima_home="$HOME/.lima"
android_lima_home="/Volumes/Android/android-lima"

if [[ ! -d "$default_lima_home/android" ]]; then
  echo "No android VM found under $default_lima_home" >&2
  exit 1
fi

if [[ "$(LIMA_HOME="$default_lima_home" limactl list --format '{{.Status}}' android 2>/dev/null)" == "Running" ]]; then
  LIMA_HOME="$default_lima_home" limactl stop android
fi

mkdir -p "$android_lima_home"
rsync -aH --sparse "$default_lima_home/" "$android_lima_home/"
test -f "$android_lima_home/android/lima.yaml"

if [[ -e "${default_lima_home}.before-android-volume" ]]; then
  echo "Backup already exists: ${default_lima_home}.before-android-volume" >&2
  exit 1
fi
mv "$default_lima_home" "${default_lima_home}.before-android-volume"
```

Verify that Lima sees the copied instance before removing the backup:

```bash
limactl list
limactl start android
limactl shell --reconnect android
```

The Lima home is `/Volumes/Android/android-lima/`; the VM itself is stored
under `/Volumes/Android/android-lima/android/`.

Create the initial VM only when `limactl list` does not show an
`android` instance:

```bash
limactl start \
  --name=android \
  --arch=aarch64 \
  --vm-type=vz \
  --mount-none \
  --cpus=12 \
  --memory=42 \
  --disk=850 \
  github:nixos-lima
```

## Deploy the NixOS configuration

The VM configuration binds the Android source tree and build cache from the
guest filesystem. Create or restore both paths before switching the VM:

```bash
limactl shell android
mkdir -p /home/ilma4.guest/.cache
git clone <your-android-repo> /home/ilma4.guest/android
exit
```

Skip the `git clone` when `/home/ilma4.guest/android` already contains the
LineageOS checkout. The directory must be on the VM disk, not a macOS Lima
mount.

From the repository root on macOS, synchronize and switch the guest with the
repository-provided deployment helper:

```bash
./utils/deploy-android-vm.sh
```

The helper copies the current flake to `/etc/nixos` and runs
`nixos-rebuild switch --flake /etc/nixos#android-vm` in the VM. If the
repository is elsewhere, set `FLAKE_LOCATION` to its path.

Restart the guest after the initial switch so the configured kernel is active:

```bash
limactl restart android
limactl shell --reconnect android
```

The SSH-backed shell automatically attaches to the `default` tmux session.
Detach with `Ctrl-b d` to leave the VM running.

## Verify the native ARM64 build environment

Inside the VM:

```bash
uname -m
getconf PAGESIZE
ulimit -n
file -L /run/current-system/sw/bin/zsh
```

The expected architecture is `aarch64`, a 4096-byte page size, and a large
open-file limit. The system binaries should be AArch64 ELF files.

## Native Android build

After switching the VM configuration, build directly from the checkout:

```bash
cd /home/ilma4.guest/android
./build-uke-vendor.sh
```

The wrapper prepares the ARM64 Go, Clang, Rust, CMake, JDK, and build-tool
prebuilts in the checkout and restores temporary compatibility files when it
exits. The 16-KiB page-size and Pixel-specific patches are not enabled.
