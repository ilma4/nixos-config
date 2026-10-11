# SMART monitoring

The NixOS base module enables smartctl exporter on physical hosts and disables
it in containers. NAS exposes it on loopback; MSI Modern exposes port 9633
through its Tailscale firewall rule. The Android VM has only virtual disks and
does not import this module. Quicksilver runs macOS and is outside this setup.

Prometheus on NAS scrapes both exporters every minute, with `host` and
`instance` labels identifying the machine. The exporter discovers disks
automatically and refreshes SMART data every five minutes. Standby checks
preserve sleeping HDDs; new disk errors become observable when the disk next
wakes and the exporter refreshes its data.

`SMARTNewErrors` fires when an observed value exceeds an earlier value in the
last hour. It covers ATA error logs, NVMe media errors and
error-log entries, and raw ATA attributes 5, 184, 187, 188, 196, 197, 198 and
199 (reallocated sectors/events, end-to-end errors, reported uncorrectable
errors, command timeouts, pending/offline uncorrectable sectors and CRC errors).
Vendor-specific raw read/seek error rates are excluded.

Existing nonzero totals at first collection establish a baseline. A decrease
alone does not trigger an alert. At least two observations are needed, so
errors that happened before monitoring began cannot be identified as new.
An alert clears when no lower observation remains in the one-hour window;
resolution means the recent increase aged out, not that the disk was repaired.
An increase after an outage longer than an hour also establishes a new baseline.
The `error` label identifies the metric or ATA attribute in the notification.

`SMARTHealthFailed` separately reports failed overall SMART health or an NVMe
critical warning, including problems already present at first collection. It
remains active while that condition is reported. NVMe error-log entries can
also reflect rejected commands; an increase calls for inspecting the log and
does not by itself establish a failing disk.

Both alerts use the existing Alertmanager receiver and ntfy topic. Detection
depends on reachable hosts and successful SMART reads; a sleeping laptop is
not treated as a disk failure.

## Validation

```sh
promtool check rules hosts/nas/prometheus/alerts.yml
promtool test rules tests/smart-alerts.test.yml
promtool test rules tests/backup-alerts.test.yml
./utils/flake-check.sh
```

After activating the NAS and MSI Modern configurations, check the
`smartctl-exporter` targets in Prometheus and query
`smartctl_device{job="smartctl-exporter"}` to inspect the discovered disks.
Configuration validation does not activate either host or test live delivery.
