# Project: nixos-config

## Project Description
Configs for nixos, home-manager and nix-darwin for my devices. All configurations use flakes

## Tech Stack
- NixOS
- Nix-Darwin
- Home-Manager
- sops-nix
- podman

## Code Conventions
- Write `set -euo pipefail` at the beginning of every bash script
- Before using options or packages ensure they exists using mcp-nixos

## Project Structure
- `flake.nix` - file describing flake
- `hosts/` - device-specific configurations
  - `hosts/quicksilver/` - macbook from jetbrains, used both as personal and work device. Runs on macOS with nix-darwin. - /nas - ugreen nassync: NAS device used as homelab. Runs on NixOS
    - `quicksilver.nix`
    - `ilma4-home.nix`
  - `hosts/laat/` - my home nas, also used as homelab. Runs on NixOS
    - `laat.nix`
    - `home.nix`
    - `nas.nix`
    - `samba.nix` - configuration for samba
    - `hdd-idle-guard.nix` - spins down hard drives after a period of inactivity
    - `docker-services/` - directory containing nix modules with docker-compose services
  - `hosts/msi-modern/` - laptop running on Ubuntu with home-manager

  - usually filename ending with `home.nix` is home-manager configuration
  - usually filename ending with `configuration.nix` is main NixOS/Nix-darwin configuration file
  - other .nix file are usually modules specific to the host

- `darwin-modules/` - nix-darwin modules
  - `launchd-agents.nix` - defines launchd agents
  
- `home/` - home-manager modules
  - `base.nix` - common configuration for all hosts
  - `fonts.nix` - configuration for fonts
  - `dev.nix` - configuration for development tools
  - `raycast.nix` - configures raycast commands (MacOS only)
  
- `modules/` - nixos modules
  - `base.nix` - common configuration for all hosts
  - `avahi.nix` - enables avahi-daemon
  - `docker-compose.nix` - allows running services using docker-compose. Provides `dockerCompose` option to define services using docker-compose
  - `docker-compose-update.nix` - automatically updates containers for services defined using `dockerCompose`
  - `home-manager.nix` - configuration for home-manager as nixos module
  - `universall-apps.nix` - provides `i4.apps` option, allows install apps on NixOS, home-manager and MacOS with nix-darwin or homebrew
  - `apps.nix` - installs apps on NixOS, home-manager and MacOS using `i4.apps` from universal-apps.nix
  - `zram.nix` - configures zram
  - `nix-settings.nix` - configures nix settings
  - `work.nix` - settings specific to work machine
  - `server.nix` - settings specific to server machines
  
- `dotfiles/` - dotfiles for programs. Usually deployed with home-manager
- `secrets/` - secrets encrypted with sops-nix

## Important Notes
- Home-Manager is used as NixOS or Nix-Darwin module where applicable
- DO NOT switch to new configuration unless specifically asked to
- When writing docker container tags, ensure that they exist
- When adding packages from nixpkgs, ensure that they exist


## Environment Setup
- `nix flake check` - to check that the configuration is correct
- `nix-rebuild` - to switch to the new configuration
- `i4-update-host <hostname>` - to switch to the new configuration on selected host (supported hosts: "ilma4-bkp", "laat")
