# Backup monitoring

NAS inspects Restic snapshot metadata on boot, daily at 07:00, and after a
Quicksilver relay result. It also runs after relay initialization or password
rotation fails. Collection has no dependency on backup success.

The collector reads metadata only, with a five-minute timeout per repository,
and pushes aggregate metrics to the existing local Pushgateway. Prometheus
scrapes them and sends alerts through Alertmanager to the existing ntfy topic.
No additional notification account or repository credentials are needed.

## Snapshot counts and freshness

Query the number of Mac snapshots:

```promql
backup_snapshot_count{source="quicksilver"}
```

The `repo` label distinguishes `nas-ssd`, `nas-hdd`, and `hetzner`. Snapshots
must match the configured Mac hostname and `/Users/ilma4`. The NAS `/srv`
backup is monitored separately as `source="nas-server",repo="nas-server"`.
Counts are gauges: retention can remove snapshots while new backups arrive.

`BackupSnapshotsOverdue` fires when the newest observed snapshot on NAS SSD,
NAS HDD, or the server repository is older than 48 hours, with five minutes of
debouncing. An inspected but empty repository also triggers this alert.
This measures snapshot creation time, not the time the snapshot was copied.
Newly copied old snapshots do not reset the freshness check.

Failed reads retain the previous count and newest timestamp. A separate
inspection failure warning fires after 15 minutes. Observations older than
30 hours are excluded from freshness and synchronization decisions.

## Replication

NAS HDD and Hetzner snapshot sets are compared in both directions. Snapshot
identity is `original` (falling back to `id`), with matching timestamp, tree,
host, user, paths, exclusions, and tags. Different copied IDs are expected;
equal counts alone do not prove synchronization.

`BackupRepositoriesDesynchronized` fires after a difference persists for
30 minutes. It is suppressed while an observed relay is running for up to
four hours. Beyond that grace period, a stuck-relay warning can also fire.
The SSD is not compared for equality because its seven-day retention is
different from the durable repositories. Historical HDD/Hetzner differences
are reported as well as newly missed snapshots; monitoring does not repair them.

The daily timer remains a fallback if the relay never starts. Recovery after
a manual repair is detected at the next collection, or by running:

```sh
sudo systemctl start i4-backup-monitoring.service
journalctl -u i4-backup-monitoring.service
```

## Partial backups

The backup runner records the raw `restic backup` result before copying and
pruning. Exit code 3 sets `backup_partial_unresolved` to 1; only exit code 0
clears it. Other errors preserve the warning. Available partial snapshots
continue to be copied.

Status survives process and machine restarts. Node exporter reads atomic
`.prom` files from `/Users/Shared/i4-backup-metrics` on Quicksilver and
`/var/lib/i4-backup-metrics` on NAS. Unreadable paths remain in
`/var/log/i4-backup.log` on the Mac and the backup journal on NAS.

`ResticBackupPartial` has no extra alert delay. Delivery still depends on
Prometheus being able to scrape the source and on Alertmanager's grouping.
Missing status for 48 hours and stale completion times over 48 hours have
separate warnings. Collector silence, missing repository metrics, and
unavailable relay state also have monitoring warnings.

## Validation

```sh
bun test tests/backup-monitoring.test.ts
promtool check rules hosts/nas/prometheus/alerts.yml
promtool test rules tests/backup-alerts.test.yml
./utils/flake-check.sh
```

These checks validate source behavior and configuration. Deployment and a live
ntfy delivery check require activating the configurations on both hosts.
