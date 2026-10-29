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

## Enable home split DNS after NAS activation

`home_dns_enabled` defaults to false because the NAS has not yet advertised the
routes. Enabling split DNS before the routing path works would send private-domain
DNS queries to an unreachable resolver.

1. Activate the NAS configuration separately when requested.
2. Verify the NAS advertises both `/32` routes and that a remote Tailscale client
   can query `192.168.1.200` over both UDP and TCP. See
   [the service verification steps](../../docs/tailscale-services.md).
3. Create a local `terraform.tfvars` containing `home_dns_enabled = true`.
   Keep this setting for subsequent runs, including on any other machine.
4. Run `terraform plan -out=changes.tfplan`. Expect one new split DNS entry:
   `ilma4.home.arpa` -> `192.168.1.200`.
5. Apply the saved plan and verify resolution using the client's OS resolver and
   HTTPS access from outside the LAN.

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
If split DNS has been enabled, set `home_dns_enabled = true` first, then import:

```bash
terraform import 'tailscale_dns_split_nameservers.home[0]' ilma4.home.arpa
```

The resources have `prevent_destroy` to catch accidental removals, including
omitting the DNS enablement variable. Review any replacement/destruction instead
of removing that protection to bypass it.

Policy edits go through Terraform. There is no separate policy-sync workflow in
this repository. Tailscale validates policy syntax and embedded policy tests
during planning. Do not add a second writer for the same policy.
