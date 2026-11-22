# Quicksilver: make `malakhov` the primary account

Quicksilver is a Kandji-managed Apple silicon Mac. Confirm with IT that the
account change and eventual deletion are permitted. This change does not
modify local accounts, MDM enrollment, or FileVault settings by itself.

## 1. Verify admin access and FileVault

While logged in as `ilma4`, make `malakhov` an administrator in **System Settings
→ Users & Groups**. Log out of `ilma4` rather than using Fast User Switching.
Log in as `malakhov` and run:

```sh
id -un
sudo -v
sudo sysadminctl -secureTokenStatus malakhov
sudo fdesetup list -extended
dscl . -read /Users/malakhov GeneratedUID
diskutil apfs listUsers /
```

`malakhov` must have a secure token, be listed by FileVault, and have `Volume
Owner: Yes` under its `GeneratedUID`. Restart and unlock FileVault as `malakhov`
at the pre-boot login screen. If any check fails, keep `ilma4` and stop.

## 2. Preserve the old account's data and access

Keep a verified copy of any personal files you still need, including files
excluded from Restic. The old local repository is `~/NoBackup/restic` when
logged in as `ilma4`; archive it and keep its password or decryption material
separately. Test a restore before relying on it. Existing NAS and Hetzner
snapshots are not deleted by this change.

Before removing the old account, verify you have independent access to your
other machines and Git remotes. In particular, Secretive keys in the old
account are not portable; test an independent key rather than assuming that
backing up the home folder will recover them. Do not copy personal keychains,
SSH credentials, or app profiles into the work account wholesale.

## 3. Move the checkout and Homebrew, then switch

From a Terminal in the `malakhov` login session, copy the checkout, including
its Git and Jujutsu metadata. Do not overwrite an existing destination.

```bash
set -euo pipefail

src=/Users/ilma4/.config/nixos-config
dst="$HOME/.config/nixos-config"
test "$(id -un)" = malakhov
test ! -e "$dst" && test ! -L "$dst" || { echo "Already exists: $dst" >&2; exit 1; }
mkdir -p "$HOME/.config"
sudo /usr/bin/rsync -a --exclude '/.direnv/' --exclude '/node_modules/' "$src/" "$dst/"
sudo /usr/sbin/chown -Rh malakhov:staff "$dst"
cd "$dst"
jj status
```

Homebrew is installed at `/opt/homebrew`. With `ilma4` logged out and no Brew
jobs running, transfer only entries owned by `ilma4` inside that prefix,
preserving group ownership and not following symlinks. Run Brew itself as
`malakhov`, not with `sudo`:

```sh
sudo /usr/bin/find -x /opt/homebrew -user ilma4 -exec /usr/sbin/chown -h malakhov {} +
/opt/homebrew/bin/brew --prefix
/opt/homebrew/bin/brew doctor
```

Resolve ownership or permission errors before switching. The existing
`cleanup = "zap"` policy can uninstall unlisted software and remove its data
on activation. If you have manually installed software to keep, compare
`brew list` with `nix eval --raw .#darwinConfigurations.quicksilver.config.homebrew.brewfile`
before switching.

```sh
cd "$HOME/.config/nixos-config"
sudo darwin-rebuild switch --flake "$PWD#quicksilver"
```

Verify that the switch succeeded, `nix-rebuild` is available in a new shell,
and work Git/Jujutsu, the 1Password SSH agent, and Homebrew work. If you use
quicksilver's remote SSH, test the existing iOS key with `malakhov`; the new
configuration no longer allows SSH as `ilma4`.

The new configuration does not run the old personal Restic backup, Home
Assistant token provisioning, Obsidian auto-commit, or MacEQ under `malakhov`.
[Splash](quicksilver-splash.md) uses model files in the new account's home.
After the switch, `pmset -g sched` may still show the old
3:55 a.m. repeating wake; if it is only the retired backup schedule, remove
it with `sudo pmset repeat cancel`. Old decrypted SOPS generations can remain
under `/run/secrets.d`; review their cleanup after securing any recovery
material. NAS backup freshness and status alerts for quicksilver will become
stale; the NAS configuration and archived repositories are unchanged.

## 4. Delete `ilma4` only after verification

From `malakhov`, with `ilma4` fully logged out, use **System Settings → Users &
Groups → ilma4 → Delete User**. Choose **Don't change the home folder**, or
save it as a disk image if there is enough space. Do not erase the only copy
of the home folder. Restart once more and confirm `malakhov` still unlocks
FileVault and can use `sudo`.
