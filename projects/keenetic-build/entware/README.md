# Entware bootstrap and update hooks

The project’s firmware supplies the Keenetic OPKG integration. The Entware runtime and packages are installed separately in OPKG storage on the router.

Reuse `bootstrap-packages.tar.gz`, the standalone `opkg` binary, and the `packages/*.ipk` files from the original workspace if needed. The archive contains the IPKs, HTTPS feed configuration, and the two shell hooks. To check the individual input packages, run `sha256sum -c SHA256SUMS` from `packages/`.

`opkg-https.conf` uses the MIPS little-endian Entware feed and Keenetic’s Entware feed over HTTPS. `opkg.conf` records the original bootstrap feed configuration.

On a router with Entware already initialized, `020-entware-autoupdate.sh` is an NDM schedule hook for the start of a schedule named `EntwareUpdate`. It calls `/opt/etc/entware-autoupdate.sh`, which serializes package updates and logs to `/tmp/entware-autoupdate.log`.
