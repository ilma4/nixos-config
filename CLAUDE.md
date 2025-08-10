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
- We use alejandra for formatting

## Project Structure
- flake.nix - file describing flake
- hosts - device-specific configurations
  - bkp - ilma4-bkp: my old laptop, used as personal device, when other are unavailable. Runs on NixOS
  - quicksilver - macbook from jetbrains, used both as personal and work device. Runs on macOS with nix-darwin. - /nas - ugreen nassync: NAS device used as homelab. Runs on NixOS
  - laat - my home nas, also used as homelab. Runs on NixOS

  - usually filename ending with `home.nix` is home-manager configuration
  - usually filename ending with `configuration.nix` is main NixOS/Nix-darwin configuration file
  - other .nix file are usually modules specific to the host

- darwin-modules - nix-darwin modules
- home - home-manager modules
- modules - nixos modules
- dotfiles - dotfiles for programs. Usually deployed with home-manager
- secrets - secrets encrypted with sops-nix

## Important Notes
- If you create new file always do `git add` before switching to the new configuration
- Home-Manager is used as NixOS or Nix-Darwin module where applicable
- You are running on quicksilver
- Always check that the configuration is correct before switching to it
- DO NOT switch to new configuration unless specifically asked to


## Environment Setup
- `nix flake check` - to check that the configuration is correct
- `nix-rebuild` - to switch to the new configuration
- `i4-update-host <hostname>` - to switch to the new configuration on selected host (supported hosts: "ilma4-bkp", "ilma4-nas")
