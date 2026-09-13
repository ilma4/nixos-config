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
    inputs.home-manager-unstable.nixosModules.home-manager
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
  programs.nix-ld = {
    enable = true;
    libraries = lib.mkForce (with pkgs; [
      glibc
      zlib
      ncurses5
      fontconfig
      libglvnd
      libx11
    ]);
  };

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

    # Initialize tmux sessions on SSH connections, including limactl shell.
    programs.zsh.initContent = ''
      if [[ -z "''${TMUX:-}" ]] && [[ -n "''${SSH_CONNECTION:-}" || -n "''${SSH_CLIENT:-}" || -n "''${SSH_TTY:-}" ]]; then
        tmux attach-session -t default || tmux new-session -s default
      fi
    '';
  };

  networking.hostName = "android-vm";

  services.lima.enable = true;
  services.openssh.enable = true;

  # Soong/Ninja opens a very large number of files during graph generation.
  # Apply the limit to login sessions and to the native VM build processes.
  security.pam.loginLimits = [
    {
      domain = "ilma4";
      type = "soft";
      item = "nofile";
      value = 4194304;
    }
    {
      domain = "ilma4";
      type = "hard";
      item = "nofile";
      value = 4194304;
    }
  ];
  systemd.services.sshd.serviceConfig.LimitNOFILE = 4194304;

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

  environment.systemPackages = with pkgs; [
    git
    gitRepo
    ccache
    python3
    bashInteractive
    coreutils
    findutils
    gnugrep
    gnused
    gawk
    which
    file
    ripgrep
    rsync
    unzip
    zip
    curl
    wget
    gnupg
    git-lfs
    perl
    gcc
    binutils
    gnumake
    flex
    bison
    bazel
    ninja
    cmake
    jdk17_headless
    jdk21_headless
    jdk8_headless
    lz4
    lzop
    bzip2
    gzip
    xz
    zstd
    cpio
    p7zip
    bc
    openssl
    kmod
    pkgsStatic.openssl.dev
    pkgsStatic.openssl.out
    zlib.dev
    elfutils
    elfutils.dev
    libxml2
    libxslt
    fontconfig
    protobuf
    e2fsprogs
    erofs-utils
    squashfsTools
    dtc
    pahole
    imagemagick
    jq
    util-linux
    android-tools
    nix
    zsh
  ];

  # The Android build invokes a few tools through conventional FHS paths.
  # Keep those paths native to this VM; no x86 compatibility runtime is
  # involved.
  systemd.tmpfiles.rules = [
    "L+ /bin/bash - - - - /run/current-system/sw/bin/bash"
    "L+ /bin/pwd - - - - /run/current-system/sw/bin/pwd"
    "L+ /usr/bin/lz4 - - - - ${pkgs.lz4.out}/bin/lz4"
    "L+ /usr/bin/pahole - - - - ${pkgs.pahole}/bin/pahole"
    "L+ /usr/bin/mogrify - - - - ${pkgs.imagemagick}/bin/mogrify"
    "L+ /usr/bin/dtc - - - - ${pkgs.dtc}/bin/dtc"
    # Android's PATH interposer expects the native Bazel executable to have a
    # stable basename. The Nix `bazel` command is a workspace wrapper that
    # delegates to a versioned basename, so point this FHS path at the raw
    # ARM64 ELF instead.
    "L+ /usr/bin/bazel - - - - ${pkgs.bazel}/bin/.bazel-7.6.0-linux-aarch64-wrapped"
  ];

  system.stateVersion = "26.05";
}
