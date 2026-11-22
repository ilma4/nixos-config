# SSH payloads and service

Keep the original `ssh-payload.tar.gz` and `openssh-payload.tar.gz` under this directory or pass their paths directly. The two manifests in `packages/` record the Entware inputs used for those payloads. With the required IPKs present, run `sha256sum -c SHA256SUMS` for the shared/Dropbear inputs or `sha256sum -c SHA256SUMS.openssh` for the additional OpenSSH inputs from that directory.

Start a temporary transfer on the host using its LAN IPv4 address and the router’s IPv4 address:

```sh
node transfer.cjs ssh-payload.tar.gz <host-ipv4> <router-ipv4>
node transfer-openssh.cjs openssh-payload.tar.gz <host-ipv4> <router-ipv4>
```

The servers serve the named archive only to the supplied router IPv4 address at `/ssh-payload.tar.gz` on port 18229 or `/openssh-payload.tar.gz` on port 18230. Stop the server after transferring the archive.

The router-side `admin-ssh-service.sh` uses the OpenSSH runtime under `/opt/ssh-admin/openssh` and a locally prepared `/opt/ssh-admin/sshd_config`. Configure authentication, account files, and host keys on the router, and keep them local. The included `initrc` starts both the SSH service and the NAT66 hook if both have been installed. For NAT66 alone, use the separate NAT66 `initrc`.
