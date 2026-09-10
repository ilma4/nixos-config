# Android development VM

The `android-vm` NixOS configuration runs as an ARM64 Lima guest. Lima is
installed on the macOS host through Home Manager (`hosts/quicksilver/ilma4-home.nix`).
The guest also uses Home Manager for the `ilma4` user and enables the shared
development environment from `home/dev.nix`; container, Nix, Rust, zsh
autoenv, and direnv extras are disabled.

## Host setup

Use `limactl-android` for the commands below. It wraps `limactl` and sets
`LIMA_HOME` to the external Android volume.

To move an existing VM from Lima's default location, stop it and move the
entire Lima home so that its shared SSH configuration is moved as well:

```bash
if [[ "$(LIMA_HOME="$HOME/.lima" limactl list --format '{{.Status}}' android)" == "Running" ]]; then
  LIMA_HOME="$HOME/.lima" limactl stop android
fi
mkdir -p /Volumes/Android/android-lima
rsync -aHAX --sparse "$HOME/.lima/" /Volumes/Android/android-lima/
rm -rf "$HOME/.lima"
```

On Apple Silicon, install Rosetta once if it is not already available:

```bash
softwareupdate --install-rosetta
```

Create the initial VM:

```bash
limactl-android start \
  --name=android \
  --vm-type=vz \
  --rosetta \
  --mount-none \
  --cpus=12 \
  --memory=42 \
  --disk=850 \
  github:nixos-lima
```

Enter it and install the configuration:

```bash
limactl-android shell android
sudo git clone <your-config-repo> /etc/nixos
sudo nixos-rebuild switch --flake /etc/nixos#android-vm
```

The SSH-backed shell automatically attaches to the `default` tmux session.
Detach with `Ctrl-b d` to leave the VM running.

Restart the guest after the initial switch:

```bash
exit
limactl-android restart android
```

The Lima home is `/Volumes/Android/android-lima/`; the VM itself is stored
under `/Volumes/Android/android-lima/android/`.

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
package set.

After switching the VM configuration, enter it with:

```bash
enter-android-devenv
uname -m
# x86_64
file -L /run/current-system/sw/bin/zsh
# ELF 64-bit ... x86-64
```

The Android build can then be started without changing the LineageOS sources:

```bash
cd /android
./build-uke.sh
```
