# Adding a new main SSH key

How to roll out a new key for `main-pub-keys` — the set of keys that grant SSH
access to all my devices.

> **Rule: always have a second backup key.** `main-pub-keys` must contain at
> least two keys stored in independent places (e.g. one in Secretive on the
> Mac, one in Bitwarden). If one of them is lost, you can still get in with
> the other and rotate. Never remove an old key before the new one is deployed
> **everywhere**, including the non-nix devices below.

## 1. Add the key to `constants.nix`

Append the public key to the `main-pub-keys` array in
[`constants.nix`](../constants.nix), with a comment saying where the private
key lives:

```nix
main-pub-keys = [
  # quicksilver secretive 'main-key'
  "ecdsa-sha2-nistp256 AAAA... ilya.malakhov4@gmail.com"

  # Bitwarden 'main-key'
  "ssh-ed25519 AAAA..."
];
```

All nix-managed hosts consume this array, so they get the new key on the next
rebuild (`nix-rebuild` locally, `i4-update-host` for remote hosts):

- `modules/base.nix` — `authorizedKeys` for my user
- `modules/initrd-ssh.nix` — initrd SSH (disk unlock)
- `hosts/nas/hoopsnake.nix`

## 2. Add the key to non-nix-configurable devices

These devices don't read `constants.nix` and must be updated **manually**:

### Hetzner storage box

Host: `u478838.your-storagebox.de`, port 23 (see `hetzer-storage` entry in
`hosts/quicksilver/ilma4-home.nix`).

Append the key to `~/.ssh/authorized_keys` on the box, e.g.:

```sh
ssh-copy-id -p 23 -i /path/to/new-key.pub u478838@u478838.your-storagebox.de
```

or edit `.ssh/authorized_keys` over sftp / in the Hetzner Robot panel.

### amd-bc-250

Append the key to `~/.ssh/authorized_keys` on the device:

```sh
ssh-copy-id -i /path/to/new-key.pub ilma4@amd-bc-250
```

## 3. Verify

- Rebuild and switch nix-managed hosts, then confirm you can SSH into each of
  them with the new key.
- Confirm SSH access to the Hetzner storage box and amd-bc-250 with the new
  key before retiring any old one.
