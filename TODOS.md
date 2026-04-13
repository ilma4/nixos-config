# Can I bike to the office without rain?

use openweather prescription map to check if I can go to the office without rain

# backup.nix

- setup local repo
- setup copy remote repos
- init local repo with chunker params from remotes
- init remotes with chunker params from local
- use rclone serve restic --stdio
- when copying check that chunker params match
- use launchd on macos and system on linux/home-manager

# Monitorings and alerts

- check status of podman containers
  - or even status of selected systemd services
- check availability of services (i.e. curl of `myservice.ilma4.local` returns 200)
- check S.M.A.R.T. of disks
- check available disk space
- check free RAM
- check CPU load
- check status of restic backups
- alerts
- collect data from multiple machines
- lightveight (can run on cheap VPS)
- simple configuration (preferrably declarative)


- wire backups to prometheus
  - get report if snapshot size increased more than 10%
    - launch codex to investigate
- server disk spaces
- smart of disks

- reachibility of my self-hosted services

- telegram notifications if someting fails

# Constants!

Define more constants to simplify secrets/path/locations etc. management

- Use constants to update the password on the restic repositories
  - activation script, that checks if the current password is working, otherwise do not apply the update
  - similar thing can be used for other "statefull services"

# /update-service command

Create a slash command for codex/claude codex/gemini so that they can update my services. I.e.:

They have to search for the newer version of the service, find the docker-compose.yml file or the docker container version and update my config to match them.

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
- make `neovim` to run simple neovim with minimal config

- make `neovim-ide` to run with heavy config

- theme, both light and dark and autoswitch
- tabs
- search files by name
- search text in files
- comments
- folding

# Always new versions of apps

- codex (check release versions on github, and use flake from their repo)
- claude-code
- junie
- container (run docker containers on mac from Apple)
