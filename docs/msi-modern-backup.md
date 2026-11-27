# msi-modern backups

The systemd timer backs up `/home/ilma4` as `ilma4` at 04:00 local time.
It requests a wake from suspend (firmware permitting) and catches up after
boot if it missed a run. The exclusion list in `hosts/msi-modern/backup.nix`
skips `NoBackup`, Downloads, caches, and other rebuildable data.

Restic keeps seven days of local snapshots in `/home/ilma4/NoBackup/restic`.
It uses Quicksilver's existing password and restricted SSH key to copy to
the same append-only NAS SSD repository over Tailscale. The NAS must be
reachable for the scheduled job. The existing 05:00 NAS relay copies both
laptops' snapshots to HDD and Hetzner with no NAS configuration changes.
Restic records them separately by hostname.

After activating the laptop configuration, check the timer and run the
first backup while connected to Tailscale:

```sh
systemctl list-timers i4-backup.timer
sudo i4-backup-run
journalctl -u i4-backup-init-local -u i4-backup-rotate-keys -u i4-backup
i4-restic-local snapshots
i4-restic-nas-ssd --no-lock snapshots --host msi-modern
```

On NAS, check for the laptop's snapshot after the relay runs:

```sh
restic -r /mnt/hdd/restic --password-file /run/secrets/restic_password/ilma4_legacy snapshots --host msi-modern
storage-box --no-lock snapshots --host msi-modern
```

The laptop exports its backup result via node exporter for partial-backup
alerts. The existing NAS repository freshness and replication alerts still
track Quicksilver snapshots only.
