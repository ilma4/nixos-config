# Troubleshooting live ISO

An ephemeral x86_64 NixOS live image with Sway, Firefox, key-only SSH and
passwordless sudo for `ilma4`. The configuration is
[`hosts/troubleshooting/iso.nix`](../hosts/troubleshooting/iso.nix), exposed as
`nixosConfigurations.troubleshooting` and `packages.x86_64-linux.troubleshooting-iso`.
It uses the repository's locked stable Nixpkgs, independently of the normal host
configuration, Home Manager and secrets.

## Build

On an x86_64 Linux machine:

```sh
mkdir -p tmp/troubleshooting-iso
nix build .#troubleshooting-iso --out-link tmp/troubleshooting-iso/result
ls tmp/troubleshooting-iso/result/iso/*.iso
```

The same derivation is available through
`.#nixosConfigurations.troubleshooting.config.system.build.isoImage`.

From macOS, archive the current source and its locked inputs to the MSI laptop,
then build there as an ordinary user:

```bash
set -euo pipefail
snapshot="$(nix flake archive --json --to ssh://msi-modern.local . | jq -r .path)"
ssh msi-modern.local \
  "mkdir -p /home/ilma4/.cache/i4-troubleshooting-iso && \
    nix build 'path:${snapshot}#packages.x86_64-linux.troubleshooting-iso' \
    --out-link /home/ilma4/.cache/i4-troubleshooting-iso/result --max-jobs 2 --cores 4"
mkdir -p tmp/troubleshooting-iso
scp 'msi-modern.local:/home/ilma4/.cache/i4-troubleshooting-iso/result/iso/*.iso' \
  tmp/troubleshooting-iso/
(cd tmp/troubleshooting-iso && shasum -a 256 ./*.iso > SHA256SUMS)
```

The explicit `path:` prefix avoids treating the archived source as a Git checkout.
This builds an artifact; it does not switch or reboot the build host. Keep generated
images out of source snapshots: `.` uses the repository's tracked files, whereas
`path:.` can include ignored build artifacts.

## Boot and access

- UEFI only, with Secure Boot disabled. No legacy BIOS support.
- The image has an explicit GPT EFI System Partition for raw USB boot, plus
  a UEFI El Torito entry for optical-media boot.
- Boot from the ISO, or write the image to a USB device using an image writer.
- `ilma4` automatically enters Sway on tty1. Other consoles provide a fallback;
  use Ctrl+Alt+F2. Exiting Sway returns to the shell; run `sway` to start it again.
- Super+Return opens Foot, Super+d opens the launcher, Super+b opens Firefox,
  Super+Shift+q closes a window, and Super+Shift+e exits Sway.
- Ethernet uses DHCP. Use `nmtui` or `nmcli` for Wi-Fi and `ip -br address` to
  find the live system's address.
- Connect with `ssh ilma4@<IP>`. Both keys in `constants.main-pub-keys` are
  authorized. Password and root SSH logins are disabled. Only public keys are
  embedded; SSH host keys are generated at boot and change between live sessions.
- `sudo` needs no password. The local account is deliberately passwordless for
  live-media use; the unused upstream `nixos` and root password logins are locked.
- Run `cat /etc/troubleshooting.txt` for a short reference.

Save recovered data and logs to another device before rebooting. The image does
not automatically mount disks for recovery, start stress tests, or repair filesystems.

## Included tools and footprint

The minimal ISO already supplies Vim, rsync, jq, tcpdump, SMART/NVMe and
PCI/USB tools, partitioning tools, cryptsetup, TestDisk/PhotoRec and GNU ddrescue.
The configuration adds LVM/mdraid tools, hardware sensors and DMI inspection,
memtester, stress-ng, ethtool, Nmap, MTR, iperf3, DNS tools, curl/wget, htop,
iotop, sysstat, strace, lsof and ripgrep. Memtest86+ is available from the UEFI
boot menu.

Filesystem support includes ext2/3/4, Btrfs, XFS, FAT, NTFS, F2FS and SMB/CIFS.
ZFS is omitted. Normal redistributable firmware is retained for portability.
The desktop uses Sway, Foot, wmenu and DejaVu fonts, without XWayland or a full
desktop environment. Firefox is included for accessing documentation and web UIs.
Speech synthesis and cellular modem services are disabled.

Utility man pages remain available. Full NixOS documentation, offline Nixpkgs
sources, Git and preloaded installer build dependencies are omitted; installing
extra Nix packages needs a network connection.

## Validation

Run `./utils/flake-check.sh`, then build and boot the actual ISO with QEMU/KVM
and OVMF on `msi-modern.local`. Use only disposable virtual disks. Test both
optical-media boot and raw-disk/USB-style UEFI boot, and confirm that the image
contains no legacy BIOS El Torito entry.

With SSH forwarded from the guest to port 2222 on the build host's loopback
interface, access the guest using the main key on the Mac, without copying or
forwarding its private key:

```sh
ssh -J msi-modern.local -p 2222 ilma4@127.0.0.1
```

Use a separate known-hosts file for disposable guests. Verify:

- `/sys/firmware/efi` exists; Sway and the initial terminal start automatically.
- Launcher and Firefox work; exiting Sway leaves a usable console.
- `sudo -n true` succeeds; the expected keys are installed; unauthorized keys,
  password authentication, and root SSH login fail.
- Networking and representative diagnostic commands work. Test filesystem
  recovery against a disposable virtual disk only.
- Memtest86+ launches from the UEFI menu.
- Record ISO size and idle memory with Sway and a terminal running, before
  launching Firefox or stress tests.

### Verified build (2026-11-05)

The image built on `msi-modern.local` is 1,961,359,360 bytes (1.83 GiB).
QEMU/KVM with OVMF, two virtual CPUs and 2 GiB RAM booted it both as optical
media and as a raw USB disk. Sway and Foot started automatically, with 370 MiB
used memory after optical boot and 369 MiB after USB boot (`free -m`). These
are VM measurements, not a guarantee for every physical machine.

Verified the launcher, Firefox, console fallback, main-key SSH, passwordless
sudo, rejection of unauthorized keys/passwords/root SSH, and absence of failed
systemd units. Memtest86+ launched from the UEFI menu. Disposable-disk tests
covered ext4 creation/checking/read-only data access and a read-only Btrfs check;
short CPU and userspace memory tests also passed. Physical NVMe, SMART and Wi-Fi
hardware were not exercised by these VM tests.
