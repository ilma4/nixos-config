# Tailscale configuration

Terraform manages the complete policy in `policy.hujson`, the provider-supported
settings in `settings.tf`, MagicDNS, search domains, and the NAS's two approved
host routes. The policy was exported from the existing tailnet, including its
existing allow-all rule and `tag:hoopsnake` ownership; no access rules were changed.

Initial adoption imported all five existing resources before applying. The only
live changes were approving `192.168.1.33/32` and `192.168.1.200/32` on the NAS,
and marking the policy as externally managed with a link to this directory.
NAS route advertisement is still managed by NixOS, not Terraform.

The provider cannot represent an empty global nameserver list, so the existing
empty list is intentionally unmanaged. Unexposed settings, such as route selection,
remain unchanged. No other split DNS domains are managed by this configuration.

## Local use

Use Terraform >= 1.5 and < 2, or a compatible OpenTofu release. Provider version
and checksums are recorded in `.terraform.lock.hcl` for Apple Silicon and Linux
amd64/arm64. No credentials are stored in these files.

Load an OAuth client through environment variables from a private file outside
version control, then run from this directory:

```bash
umask 077
terraform init
terraform fmt -check
terraform validate
terraform plan -out=changes.tfplan
terraform apply changes.tfplan
terraform plan -detailed-exitcode
```

The final command should exit 0 (no changes); 2 means changes are proposed.
Required OAuth scopes: `dns`, `devices:routes`, `policy_file`,
`devices:posture_attributes`, and `feature_settings` with write access, plus
`devices:core:read`. Policy writes require the device/posture scopes too.
See the [scope reference](https://tailscale.com/docs/reference/trust-credentials).

## Home split DNS

`home_dns_enabled` defaults to true in the checked-in configuration. Queries for
`ilma4.home.arpa` use Pi-hole at `192.168.1.200`; other DNS remains unchanged.
The NAS routing configuration has been activated, and both host routes are
advertised and approved. No local variable file is needed to enable split DNS.

Verify DNS resolution using the client's OS resolver and HTTPS access from
outside the LAN. See [the service verification steps](../../docs/tailscale-services.md).
The NAS and its Pi-hole routing path must remain available for these queries.

The two routes are approved already; no manual route approval is needed.
The existing policy already allows the DNS/HTTPS traffic. Preserve the existing
certificate trust on each client. Linux clients must accept subnet routes.

## State and recovery

State is local in `terraform.tfstate`, with Terraform's local state locking. Keep
that file, its backup, local variable files, credentials, and saved plans private;
they are ignored by Jujutsu/Git. Back up the state and local variables securely.
There is no GitHub Actions apply workflow. Before adding CI or running from
multiple machines, migrate state to a persistent remote backend with locking.
Do not run independent local states against this tailnet.

If the local state is lost, restore its backup. If no backup exists, import the
existing resources before planning:

```bash
terraform import tailscale_acl.policy acl
terraform import tailscale_tailnet_settings.settings tailnet_settings
terraform import tailscale_dns_preferences.dns dns_preferences
terraform import tailscale_dns_search_paths.search dns_search_paths
terraform import tailscale_device_subnet_routes.nas '<NAS_NODE_ID>'
```

Use the NAS's stable node ID from the Tailscale API, not a different device.
Split DNS is enabled by default. Import the existing entry as well:

```bash
terraform import 'tailscale_dns_split_nameservers.home[0]' ilma4.home.arpa
```

The resources have `prevent_destroy` to catch accidental removals, including
explicitly disabling split DNS. Review any replacement/destruction instead
of removing that protection to bypass it.

Policy edits go through Terraform. There is no separate policy-sync workflow in
this repository. Tailscale validates policy syntax and embedded policy tests
during planning. Do not add a second writer for the same policy.
