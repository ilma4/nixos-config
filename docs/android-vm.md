# Android development VM

The `android-vm` NixOS configuration runs as an ARM64 Lima guest. Lima is
installed on the macOS host through Home Manager (`hosts/quicksilver/ilma4-home.nix`).
The guest also uses Home Manager for the `ilma4` user and enables the shared
development environment from `home/dev.nix`; container, Nix, Rust, zsh
autoenv, and direnv extras are disabled.

## Host setup

The Android VM uses a separate Lima home on the external volume. Mount the
volume at `/Volumes/Android` before running any Lima command, and use
`limactl-android` for every command below. It sets `LIMA_HOME` to
`/Volumes/Android/android-lima`; mixing it with plain `limactl` makes the VM
appear to be missing because Lima will look in `~/.lima` instead.

`limactl-android` is installed by the quicksilver Home Manager configuration.
While bootstrapping that configuration, replace it with
`LIMA_HOME=/Volumes/Android/android-lima limactl`.

### Recover an unavailable VM

Check the instance and confirm that the external volume is mounted:

```bash
test -d /Volumes/Android/android-lima
limactl-android list
```

If the instance is stopped, start the existing instance rather than creating a
new one:

```bash
limactl-android start android
```

Lima can show the instance as `Running` while the guest network or SSH server
is no longer reachable. If `shell` reports `Connection reset by peer`, `no
route to host`, or hangs, restart the instance and request a fresh SSH
connection:

```bash
limactl-android restart android
limactl-android shell --reconnect android
```

If restart does not recover it, do a full stop/start without deleting the
instance or its disk:

```bash
limactl-android stop android
limactl-android start android
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

Verify that the wrapper sees the copied instance before removing the backup:

```bash
limactl-android list
limactl-android start android
limactl-android shell --reconnect android
```

The Lima home is `/Volumes/Android/android-lima/`; the VM itself is stored
under `/Volumes/Android/android-lima/android/`.

On Apple Silicon, install Rosetta once if it is not already available:

```bash
softwareupdate --install-rosetta
```

Create the initial VM only when `limactl-android list` does not show an
`android` instance:

```bash
limactl-android start \
  --name=android \
  --arch=aarch64 \
  --vm-type=vz \
  --rosetta \
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
limactl-android shell android
mkdir -p /home/ilma4.guest/.cache
git clone <your-android-repo> /home/ilma4.guest/android
exit
```

Skip the `git clone` when `/home/ilma4.guest/android` already contains the
LineageOS checkout. The directory must be on the VM disk, not a macOS Lima
mount; `/android` in the container is a bind mount of this path.

From the repository root on macOS, synchronize and switch the guest with the
repository-provided deployment helper:

```bash
./utils/deploy-android-vm.sh
```

The helper copies the current flake to `/etc/nixos` and runs
`nixos-rebuild switch --flake /etc/nixos#android-vm` in the VM. If the
repository is elsewhere, set `FLAKE_LOCATION` to its path.

Restart the guest after the initial switch so the configured kernel and
Rosetta support are active:

```bash
limactl-android restart android
limactl-android shell --reconnect android
```

The SSH-backed shell automatically attaches to the `default` tmux session.
Detach with `Ctrl-b d` to leave the VM running.

## Verify Rosetta support

Inside the VM:

```bash
uname -m
zgrep -E 'ARM64_(MEMORY_MODEL_CONTROL|ACTLR_STATE)' /proc/config.gz
```

The expected architecture is `aarch64`, with both kernel options enabled.

## Android x86-64 container

The VM declares an `android-dev` NixOS container. It uses the existing
`/home/ilma4.guest/android` checkout as `/android`, and its x86-64 userspace
is executed through the VM's Rosetta binfmt registration.
The container keeps its systemd supervisor native to the ARM64 VM because a
translated systemd PID 1 cannot initialize reliably under Rosetta; the shell,
toolchain, and Android prebuilts remain x86-64.
The container imports the host's Home Manager base configuration, so
`enter-android-devenv` opens the same configured zsh shell with an x86-64
package set. Pi is explicitly enabled for the container. The `pi` executable
is installed from npm into `/home/ilma4/.local/bin` by Home Manager's
`i4-update-pi` user timer; it is not a Nix package in the system closure. The
container user therefore has lingering enabled so that timer runs even though
the container is entered through `su` rather than a normal login session.

After switching the VM configuration, enter the VM with
`limactl-android shell --reconnect android`, then run the following inside the
VM (not on macOS):

```bash
enter-android-devenv
# enters the container shell in the VM's native ARM64 tmux session
uname -m
# x86_64
file -L /run/current-system/sw/bin/zsh
# ELF 64-bit ... x86-64
```

If the container does not start, check the bind-mount paths and service log
inside the VM:

```bash
ls -ld /home/ilma4.guest/android /home/ilma4.guest/.cache
sudo systemctl status --no-pager container@android-dev.service
sudo journalctl -b -u container@android-dev.service --no-pager
```

`enter-android-devenv` keeps the multiplexer on the VM's native ARM64 side.
The container shell is a pane in that host session; it does not start the
x86-64 `tmux` binary through Rosetta. Detach with `Ctrl-b d` to leave the
container and keep the VM running.

The Android build can then be started without changing the LineageOS sources:

```bash
cd /android
./build-uke.sh
```
