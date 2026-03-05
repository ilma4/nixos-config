# Constants!

Define more constants to simplify secrets/path/locations etc. management

- Use constants to update the password on the restic repositories
  - activation script, that checks if the current password is working, otherwise do not apply the update
  - similar thing can be used for other "statefull services"

# /update-service command

Create a slash command for codex/claude codex/gemini so that they can update my services. I.e.:

They have to search for the newer version of the service, find the docker-compose.yml file or the docker container version and update my config to match them.

# Create restic-chuncker-donor repo and use it to create every new restic repository

- safe wrapper around `restic copy` which also check if repositories have the same chunker params

# better restic-repos.nix

- convert creation to systemd service so there will be error logs and faster activation
- launchd on macos?

# setup homebrew autoupdates

# Configs for msi-moder Ubuntu

## Autoinstall config

- autoinstall like in ubuntu-vm
- make it work with Ventoy
- how to add secrets here?

## Script to setup everything on ubuntu itself

- swap
- zswap
- libvirt + qemu-kvm
- packages
  - ???
- allow to use it as nix builder
- wakeup-on-lan and autosleep

# Better neovim config

- theme, both light and dark and autoswitch
- tabs
- search files by name
- search text in files
- comments
- folding
