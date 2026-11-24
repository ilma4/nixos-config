# nixos-config

`nix-rebuild` switches the local configuration from a private temporary Git
snapshot. It includes edited and new files unless they match `.gitignore`, and
passes the snapshot to Nix as `git+file://`. The original checkout and index are
left alone, and any lock-file changes made by the rebuild stay in the temporary
copy. Run `nix flake update` in the checkout to persist input updates.
