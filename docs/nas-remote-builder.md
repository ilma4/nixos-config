# NAS remote builder

The NAS can send eligible `x86_64-linux` builds to `msi-modern.local` over
LAN SSH (up to two concurrent remote jobs). Local build slots stay enabled
so the NAS can still build when the laptop is asleep or away. No Tailscale
hostname is configured for the builder.

Deploy `msi-modern` first, then `nas`. On the NAS, check the connection with:

```sh
sudo nix store info --store 'ssh-ng://nix-builder@msi-modern.local?ssh-key=/run/secrets/nas-msi-modern-builder-ssh-key'
```

The laptop pins this account to the NAS's LAN IPv4 address and the dedicated
key. The NAS pins the laptop's SSH host key. If the laptop is reinstalled,
verify its new host key locally before updating `hosts/nas/remote-builder.nix`.
To rotate the client key, remove `nas-msi-modern-builder-ssh-key` from SOPS
with `i4-sops-sudo unset`, run `scripts/nix-builder/create-secrets.sh`, and
install the printed public key in `hosts/msi-modern/remote-builder.nix`.
