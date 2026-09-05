# Android development VM

The `android-vm` NixOS configuration runs as an ARM64 Lima guest. Lima is
installed on the macOS host through Home Manager (`hosts/quicksilver/ilma4-home.nix`).

## Host setup

On Apple Silicon, install Rosetta once if it is not already available:

```bash
softwareupdate --install-rosetta
```

Create the initial VM:

```bash
limactl start \
  --name=android \
  --vm-type=vz \
  --rosetta \
  --mount-none \
  --cpus=12 \
  --memory=48 \
  --disk=100 \
  github:nixos-lima
```

Enter it and install the configuration:

```bash
limactl shell android
sudo git clone <your-config-repo> /etc/nixos
sudo nixos-rebuild boot --flake /etc/nixos#android-vm
```

Restart the guest after the first boot build:

```bash
exit
limactl restart android
```

The VM is stored under `~/.lima/android/`.

## Verify Rosetta support

Inside the VM:

```bash
uname -m
zgrep -E 'ARM64_(MEMORY_MODEL_CONTROL|ACTLR_STATE)' /proc/config.gz
```

The expected architecture is `aarch64`, with both kernel options enabled.
