{
  config,
  constants,
  inputs,
  lib,
  modulesPath,
  pkgs,
  pkgs-unstable,
  ...
}: {
  imports = [
    inputs.home-manager.nixosModules.home-manager
    (modulesPath + "/profiles/qemu-guest.nix")
  ];

  nixpkgs.config.allowUnfree = true;

  home-manager.useGlobalPkgs = true;
  home-manager.extraSpecialArgs = {
    inherit inputs;
    inherit pkgs-unstable;
    inherit constants;
  };

  users.users.ilma4 = {
    uid = 501;
    home = "/home/ilma4.guest";
    group = "users";
    shell = pkgs.zsh;
    extraGroups = ["wheel"];
  };

  programs.zsh.enable = true;
  programs.nix-ld.enable = true;

  home-manager.users.ilma4 = {
    imports = [../../home/base.nix];

    home.homeDirectory = lib.mkForce "/home/ilma4.guest";
    rebuild-script = "sudo nixos-rebuild switch --flake /etc/nixos#android-vm";

    i4.dev = {
      enable = true;
      podman = false;
      nix = false;
      rust = false;
      zshAutoenv = false;
    };

    programs.direnv.enable = false;

    # Initialize tmux sessions on SSH connections, including `limactl shell`.
    programs.zsh.initContent = ''
      if [[ -z "''${TMUX:-}" ]] && [[ -n "''${SSH_CONNECTION:-}" || -n "''${SSH_CLIENT:-}" || -n "''${SSH_TTY:-}" ]]; then
        tmux attach-session -t default || tmux new-session -s default
      fi
    '';
  };

  networking.hostName = "android-vm";

  services.lima.enable = true;
  services.openssh.enable = true;

  users.mutableUsers = true;
  security.sudo.wheelNeedsPassword = false;

  nix.settings.experimental-features = [
    "nix-command"
    "flakes"
  ];

  boot.loader.grub.enable = false;
  boot.loader.systemd-boot.enable = true;
  boot.loader.systemd-boot.configurationLimit = 1;

  fileSystems."/boot" = {
    device = lib.mkForce "/dev/vda1";
    fsType = "vfat";
  };

  fileSystems."/" = {
    device = "/dev/disk/by-label/nixos";
    fsType = "ext4";
    autoResize = true;
    options = ["noatime"];
  };

  boot.kernelPackages = pkgs.linux-asahi;

  environment.systemPackages = with pkgs; [
    git
    gitRepo
    ccache
    python3
    rsync
    unzip
    zip
    curl
  ];

  system.stateVersion = "26.05";
}
