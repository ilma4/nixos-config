# Local mail archive

The credential-free configuration prepares hydroxide → mbsync → Maildir →
Dovecot → Cypht on the NAS. OpenClaw reads the Maildir and separate notmuch
index through read-only virtiofs exports. It receives no mail passwords.

## Current stage

- `mailstore` (UID/GID 807) owns `/srv/mail`, `/var/lib/mail-archive`, and
  `/var/lib/mail-index`, with private directories and a `0077` service umask.
- Dovecot 2.4 listens only on `127.0.0.1:1144`. Its initial password file is
  empty, so **no login can succeed**. PAM/system-account login is disabled.
- Hydroxide and the download timer have no boot target until
  `i4.mailArchive.sync.enable` is enabled. The download service also requires
  all six runtime login/password files before it can run.
- Local indexing starts at boot and repeats two minutes after completion.
  No real identity is needed to index or read mail. An empty index is normal.
- Cypht uses IMAP authentication against local Dovecot, file-based settings,
  PHP sessions, and a passwordless local SQLite database. SMTP is disabled.
  Its image is pinned by digest. The HTTPS endpoint is
  `https://cypht.ilma4.home.arpa` through the existing Traefik certificate.
- Cypht's HTTP listeners use `127.0.0.1:8088` and `10.20.0.1:8088`.
  Only loopback and Traefik (`10.20.0.2`) may reach them. PHP-FPM remains on
  loopback. The Cypht container receives neither the Maildir nor any host socket.
- The OpenClaw VM gets notmuch, its public configuration, and the managed
  `~/.openclaw/skills/mail-archive` skill. Private mode-0600 mail remains
  readable through export-specific UID/GID mapping. Host `virtiofsd --readonly`
  prevents writes even if guest root changes its mount flags.

Changes must be built and explicitly switched before these services are live.
This stage does not authenticate providers or import mail. OpenClaw itself is
not installed or onboarded by the archive configuration; the skill is prepared
for its eventual installation in the existing VM. Execute mail commands inside
that VM, and do not configure NAS execution nodes, forward a host SSH agent,
or supply host login keys or management sockets to OpenClaw.

## Later: add credentials

These steps are intentionally deferred. Do not send passwords through chat.
The secret helper prompts on the terminal and sends JSON values to the
repository sops wrapper over stdin, without plaintext temporary files.

1. Enable Gmail IMAP/app-password access and Yandex IMAP/app-password access.
   Use a full Gmail address; use the Yandex username required by the account
   (normally the part before `@`). Run:

   ```bash
   ./scripts/mail-archive/create-secrets.sh gmail
   ./scripts/mail-archive/create-secrets.sh yandex
   ```

2. After activating the prepared configuration, authenticate Proton on the NAS:

   ```bash
   sudo -u mailstore env HOME=/var/lib/mail-archive hydroxide auth YOUR_PROTON_USERNAME
   ```

   Save the generated **bridge password**, then run the helper with `proton`.
   Preserve `/var/lib/mail-archive`; its hydroxide authentication state is
   encrypted with that bridge password. Never use the Proton account password
   as the mbsync password.

3. On the NAS, generate a different local password for each of `gmail`,
   `yandex`, and `proton`, using `doveadm pw -s ARGON2ID`. Keep the plaintext
   passwords in your password manager. Run the helper with `dovecot` and
   supply the three complete hashes. These local passwords also allow Cypht
   login, because Cypht authenticates against Dovecot.

4. Add runtime declarations in the NAS mail-archive module (which then needs
   `config` and `lib` arguments):

   ```nix
   sops.secrets = lib.genAttrs [
     "mail-gmail-user" "mail-gmail"
     "mail-yandex-user" "mail-yandex"
     "mail-proton-user" "mail-proton"
   ] (_: { owner = "mailstore"; group = "mailstore"; mode = "0400"; }) // {
     mail-dovecot-users = {
       owner = "root";
       group = "dovecot2";
       mode = "0440";
       restartUnits = ["dovecot.service"];
     };
   };
   i4.mailArchive.passwordFile = config.sops.secrets.mail-dovecot-users.path;
   ```

   This yields `/run/secrets/mail-PROVIDER-user`, `/run/secrets/mail-PROVIDER`,
   and `/run/secrets/mail-dovecot-users`. The credential-free stage declares
   none of these secrets, so missing keys cannot break sops activation.

5. Build, explicitly activate, and validate before enabling the download timer:

   ```bash
   sudo doveconf -n
   sudo doveadm auth test gmail
   sudo doveadm user gmail
   sudo systemctl start mail-archive-hydroxide.service
   sudo -u mailstore env HOME=/var/lib/mail-archive mbsync -c /etc/mail-archive/mbsyncrc -l -a
   sudo systemctl start mail-archive-sync.service
   ```

   Check every account's folders, message bodies, nested folders, and
   attachments. Hydroxide labels its IMAP implementation as work in progress;
   a running service alone does not validate the Proton import. Then set
   `i4.mailArchive.sync.enable = true`, validate, and explicitly switch again.
   The timer runs two minutes after boot and two minutes after each completion.

6. Log into Cypht with a local archive login (for example `gmail`). In
   **Settings → Servers**, add the local `gmail`, `yandex`, and `proton`
   accounts at `127.0.0.1:1144`, encryption **None**, using their separate local
   passwords. Save settings. Do not add provider credentials or SMTP servers.

## Semantics and maintenance

`Sync PullNew`, `Create Near`, `Remove None`, and `Expunge None` download new
messages without propagating later flags or deletions. Provider deletions
retain existing local copies. Reading, moving, or deleting through Cypht only
changes local mail. Local deletion is real: this is an editable archive, not
immutable storage. Gmail labels may create multiple local files. Only mail
still held by a provider can be imported.

With the guide's `Patterns *` and `Create Near`, folders created only in Cypht
stay local but cause mbsync to report that the corresponding upstream folder
cannot be opened. Downloads from other folders and indexing still run, and the
service reports the error. This also applies to archived folders that disappear
upstream. The archive never creates those folders at the provider to silence it.

The sync service always attempts indexing after mbsync exits, then reports a
download failure in preference to an indexing failure. Both indexing paths
share a lock. The independent index timer also picks up local Cypht changes.
notmuch tags do not synchronize Maildir flags.

From the OpenClaw VM, search and read with:

```bash
notmuch --config=/etc/mail-archive/notmuch-config search --format=json --limit=30 'date:30d..now AND (invoice OR Rechnung)'
notmuch --config=/etc/mail-archive/notmuch-config show --format=json --entire-thread=false 'thread:THREAD_ID'
```

Use `journalctl -u mail-archive-sync -u mail-archive-index` on the NAS to inspect
failures. Do not give OpenClaw a NAS shell to repair the index.

The existing Restic `/srv` source covers Maildirs, mbsync/Dovecot metadata, and
Cypht's persistent settings under `/srv/cypht`. The configuration adds
`/var/lib/mail-archive` for hydroxide state. Encrypted secrets and source
configuration remain in this repository. The notmuch index is rebuildable and
is not backed up; add it to backup coverage before storing irreplaceable tags.

## Validation

```bash
./utils/flake-check.sh
nix build .#checks.x86_64-linux.mail-archive
```

The Linux integration test uses disposable IMAP accounts and a nested QEMU VM.
It checks partial download failure, indexing, attachments, retention after
upstream deletion, local-only changes, and read-only guest access. It never
connects to real providers. It can use TCG when nested KVM is unavailable.

After building the NAS configuration, run the separate Cypht smoke test on a
Linux builder with Podman and Python/PyYAML available:

```bash
nix eval --raw .#nixosConfigurations.nas.config.dockerCompose.cypht.composeText > /tmp/mail-archive-cypht.yml
sudo python3 tests/mail-archive-cypht.py /tmp/mail-archive-cypht.yml
```

This uses temporary storage and an isolated network namespace, publishes no
ports, and removes the container afterward. It verifies SQLite startup,
rejected login, nginx configuration, and the loopback-only PHP-FPM listener.
