# Tailscale configuration

Terraform manages the complete policy in `policy.hujson`, the provider-supported
settings in `settings.tf`, MagicDNS, search domains, and the NAS's approved
`192.168.0.0/23` route. The policy preserves `tag:hoopsnake` ownership and
connectivity between Tailscale devices over IPv4 and IPv6. Subnet access is
limited to the NAS (`192.168.1.33`) and Pi-hole (`192.168.1.200`), keeping the
broader route from exposing additional LAN hosts.

Initial adoption imported all five existing resources before applying. The only
live changes were approving `192.168.1.33/32` and `192.168.1.200/32` on the NAS,
and marking the policy as externally managed with a link to this directory.
NAS route advertisement is still managed by NixOS, not Terraform.

The provider cannot represent an empty global nameserver list, so the existing
empty list is intentionally unmanaged. Unexposed settings, such as route selection,
remain unchanged. No other split DNS domains are managed by this configuration.

## Local use

From the repository root, enter the tool shell and store a dedicated Tailscale
OAuth client once. The setup script prompts without echo and stores the pair
encrypted in `secrets/example.yaml` using the repository's SOPS age key. Rerun it
to rotate the pair. Use a Terraform OAuth client, not a device auth key or the
Hoopsnake client.

```bash
nix develop .#tailscale-terraform
./scripts/tailscale-terraform/create-secrets.sh
```

If the script reports a missing or unusable age key, restore an existing identity
that can decrypt `secrets/example.yaml` (for example, the Bitwarden backup key).
The usual user key path is `~/.config/sops/age/keys.txt`; if your identity is
stored elsewhere, export `SOPS_AGE_KEY_FILE` with its absolute path before running
the scripts. Keep the key file private (`chmod 600`). A newly generated key alone
cannot decrypt the existing file.

Then run:

```bash
./infra/tailscale/terraform.sh validate  # Format and configuration checks; no credentials needed
./infra/tailscale/terraform.sh plan      # Preview live changes without applying
./infra/tailscale/terraform.sh deploy    # Review the new plan, then type yes to apply
```

`plan` and `deploy` need access to the SOPS age key and the existing local
`infra/tailscale/terraform.tfstate`. They decrypt the credentials only for the
Terraform process. The provider version and checksums are pinned in
`.terraform.lock.hcl` for Apple Silicon and Linux amd64/arm64.

Required OAuth scopes: `dns`, `devices:routes`, `policy_file`,
`devices:posture_attributes`, and `feature_settings` with write access, plus
`devices:core:read`. Policy writes require the device/posture scopes too.
See the [scope reference](https://tailscale.com/docs/reference/trust-credentials).

## Home split DNS

`home_dns_enabled` defaults to true in the checked-in configuration. Queries for
`ilma4.home.arpa` use Pi-hole at `192.168.1.200`; other DNS remains unchanged.
No local variable file is needed to enable split DNS.

The `/23` replaces the initially deployed two `/32` routes so the home LAN's
more specific `/24` takes precedence locally. This migration requires both a
Terraform apply and a NAS deployment; editing these files does not change live
routing. Apply Terraform first to restrict access and replace the approvals,
then deploy the NAS to advertise the new route. Use a direct LAN connection
because remote DNS/HTTPS may be interrupted between these steps. Withdraw both
old `/32` routes; leaving either advertised and approved defeats LAN priority.

Verify DNS resolution using the client's OS resolver and HTTPS access from
outside the LAN. See [the service verification steps](../../docs/tailscale-services.md).
The NAS and its Pi-hole routing path must remain available for these queries.

Terraform manages route approval and permits DNS/HTTPS to the two LAN hosts.
Embedded policy tests check those allowances and deny access to other LAN hosts.
Preserve the existing certificate trust on each client. Linux clients must accept
subnet routes. A remote network also using `192.168.1.0/24` will prefer its own
LAN too; overlapping networks require a separate addressing solution.

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
