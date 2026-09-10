{
  config,
  constants,
  inputs,
  lib,
  modulesPath,
  pkgs,
  pkgs-unstable,
  ...
}: let
  containerName = "android-dev";
  androidCheckout = "/home/ilma4.guest/android";
  androidCache = "/home/ilma4.guest/.cache";

  enterAndroidDevenv = pkgs.writeShellApplication {
    name = "enter-android-devenv";
    runtimeInputs = [
      pkgs.nixos-container
      pkgs.systemd
      pkgs.tmux
      pkgs.util-linux
    ];

    text = ''
      set -euo pipefail

      # Keep the persistent multiplexer native to the ARM64 VM.  The shell
      # below becomes a pane in this host tmux; never start the x86-64
      # container's tmux under Rosetta.
      if [[ -z "''${TMUX:-}" ]]; then
        exec tmux new-session -A -s android-dev "$0" "$@"
      fi

      if ! systemctl is-active --quiet container@${containerName}.service; then
        sudo nixos-container start ${containerName}
      fi

      containerLeader=""
      for _ in {1..30}; do
        containerLeader="$(sudo machinectl show ${containerName} -p Leader --value 2>/dev/null || true)"
        if [[ -n "$containerLeader" && "$containerLeader" != "0" ]]; then
          break
        fi
        sleep 1
      done

      if [[ -z "$containerLeader" || "$containerLeader" == "0" ]]; then
        echo "Unable to find the ${containerName} container leader" >&2
        exit 1
      fi

      # Use the container's x86-64 su after entering its mount namespace.
      # nixos-container run uses the host ARM64 su, which cannot load the
      # container's x86-64 PAM modules under Rosetta.
      exec sudo nsenter --all -t "$containerLeader" -- \
        /run/current-system/sw/bin/su - ilma4 -c \
        'cd /android && export ANDROID_DEV_NO_TMUX=1 && exec zsh -l'
    '';
  };
in {
  imports = [
    inputs.home-manager.nixosModules.home-manager
    (modulesPath + "/profiles/qemu-guest.nix")
    (modulesPath + "/virtualisation/rosetta.nix")
  ];

  virtualisation.rosetta = {
    enable = true;
    mountTag = "vz-rosetta";
  };

  containers.${containerName} = {
    autoStart = true;
    privateNetwork = false;
    nixpkgs = inputs.nixpkgs-unstable;

    # Keep the existing checkout and its build output on the VM filesystem.
    bindMounts."/android" = {
      hostPath = androidCheckout;
      isReadOnly = false;
    };

    bindMounts."/home/ilma4/.cache" = {
      hostPath = androidCache;
      isReadOnly = false;
    };

    # Keep the container supervisor native to the ARM64 VM. The x86-64
    # systemd PID 1 cannot initialize its manager under Rosetta, while the
    # Android userspace and build tools below still use the x86-64 platform.
    specialArgs = {
      hostPkgs = pkgs-unstable;
    };

    config = {lib, hostPkgs, pkgs, ...}: {
      imports = [
        inputs.home-manager-unstable.nixosModules.home-manager
      ];

      # nixos-containers otherwise injects the ARM64 host platform here.
      nixpkgs.hostPlatform = lib.mkForce "x86_64-linux";
      nixpkgs.config.allowUnfree = true;

      networking.hostName = containerName;

      systemd.package = hostPkgs.systemd;
      services.logrotate.enable = false; # use logrotate from host

      users.users.ilma4 = {
        # Keep the UID used by the VM checkout so the bind mount remains
        # writable without changing the LineageOS tree's ownership.
        isSystemUser = true;
        uid = 501;
        group = "users";
        home = "/home/ilma4";
        createHome = true;
        shell = pkgs.zsh;
        # pi is installed by a Home Manager systemd.user timer. Keep the
        # user manager alive even though the container is entered via su.
        linger = true;
      };

      programs.zsh.enable = true;

      # Use the same Home Manager zsh configuration as the VM host, evaluated
      # with the container's x86-64 package set.
      home-manager.useGlobalPkgs = true;
      home-manager.useUserPackages = true;
      home-manager.extraSpecialArgs = {
        inherit inputs constants;
        pkgs-unstable = pkgs;
      };

      home-manager.users.ilma4 = {
        imports = [../../home/base.nix];

        home.homeDirectory = lib.mkForce "/home/ilma4";

        i4.dev = {
          enable = true;
          podman = false;
          nix = false;
          rust = false;
          zshAutoenv = false;
        };
        # Be explicit here: the npm-installed Pi agent is part of this
        # container's development environment, not just the ARM64 host's.
        i4.pi.enable = true;

        programs.direnv.enable = false;

        # The native ARM64 VM tmux owns persistent sessions. Do not start an
        # x86-64 tmux server inside the Rosetta-translated container.
        programs.zsh.initContent = ''
        '';
      };

      # The LineageOS/AOSP prebuilts are ordinary dynamically linked x86-64
      # binaries rather than Nix-built executables.
      programs.nix-ld = {
        enable = true;
        libraries = with pkgs; [
          stdenv.cc.cc
          glibc
          zlib
          ncurses5
          openssl
          fontconfig
          libglvnd
          # The old xorg.libX11 spelling is now deprecated.
          libx11
        ];
      };

      nix.settings.experimental-features = [
        "nix-command"
        "flakes"
      ];

      environment.systemPackages = with pkgs; [
        # Basic shell utilities
        bashInteractive
        coreutils
        findutils
        gnugrep
        gnused
        gawk
        which
        file

        ccache

        # Source management
        git
        gitRepo
        git-lfs
        gnupg
        curl
        wget

        # Scripts
        python3
        perl

        # Build tools
        gcc
        binutils
        gnumake
        flex
        bison
        jdk17_headless

        # Archives / compression
        zip
        unzip
        bzip2
        gzip
        xz
        zstd
        lz4
        lzop
        cpio
        p7zip

        # Common Android build dependencies
        bc
        rsync
        openssl
        libxml2
        libxslt
        fontconfig
        protobuf

        # Image / filesystem tools useful for device bring-up
        e2fsprogs
        erofs-utils
        squashfsTools
        dtc

        # Miscellaneous and Android platform tools
        jq
        util-linux
        android-tools
        nix
        zsh
      ];

      environment.variables = {
        LANG = lib.mkForce "C.UTF-8";
        LC_ALL = "C.UTF-8";
        USE_CCACHE = "1";
        CCACHE_EXEC = "${pkgs.ccache}/bin/ccache";
        CCACHE_DIR = "/home/ilma4/.cache/lineage-ccache";
      };

      # AOSP's envsetup uses this FHS path literally. NixOS intentionally
      # keeps most commands under /run/current-system/sw, so provide the
      # one compatibility link needed by the unmodified build sources.
      systemd.tmpfiles.rules = [
        "L+ /bin/bash - - - - /run/current-system/sw/bin/bash"
        "L+ /bin/pwd - - - - /run/current-system/sw/bin/pwd"
      ];

      system.stateVersion = "26.05";
    };
  };

  # systemd-nspawn waits for a READY notification from the translated inner
  # systemd, which is not delivered reliably when PID 1 is native ARM64.
  # The container remains supervised by nspawn; mark the host unit active as
  # soon as nspawn has been spawned instead.
  systemd.services."container@${containerName}".serviceConfig.Type = lib.mkForce "simple";

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

  # asahi-kernel uses 16-KiB page size. x86-64 binaries expect 4-KiB, thus its impossible to use rosetta translator
  # boot.kernelPackages = pkgs.linux-asahi;

  environment.systemPackages = with pkgs; [
    git
    gitRepo
    ccache
    python3
    rsync
    unzip
    zip
    curl
    enterAndroidDevenv
  ];

  system.stateVersion = "26.05";
}
