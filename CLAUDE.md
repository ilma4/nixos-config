# Project: nixos-config

## Project Description
Configs for nixos, home-manager and nix-darwin for my devices. All configurations use flakes

## Tech Stack
- NixOS
- Home-Manager
- Nix-Darwin
- sops-nix
- podman

## Code Conventions
- We use alejandra for formatting

## Project Structure
- /flake.nix - file describing flake
- /hosts - device-specific configurations
  - /bkp - ilma4-bkp: my old laptop, used as personal device, when other are unavailable. Runs on NixOS
  - /jb-macbook - macbook from jetbrains, used both as personal and work device. Runs on macOS with nix-darwin. - /nas - ugreen nassync: NAS device used as homelab. Runs on NixOS
- /darwin-modules - nix-darwin modules
- /home - home-manager modules
- /modules - nixos modules
- /dotfiles - dotfiles for programs. Usually deployed with home-manager
- /secrets - secrets encrypted with sops-nix

## Important Notes
- If you create new file always do `git add` before switching to the new configuration
- Always check that the configuration is correct before switching to it


## Environment Setup
- `nix-rebuild` - to switch to the new configuration
- `nix flake check` - to check that the configuration is correct
