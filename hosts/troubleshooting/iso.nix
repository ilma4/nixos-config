{
  config,
  lib,
  pkgs,
  modulesPath,
  constants,
  ...
}: {
  imports = [
    "${modulesPath}/installer/cd-dvd/installation-cd-minimal.nix"
  ];

  networking.hostName = "troubleshooting";
  time.timeZone = "Europe/Berlin";
  i18n.defaultLocale = "en_US.UTF-8";

  isoImage = {
    edition = "troubleshooting";
    volumeID = "NIXOS_TROUBLESHOOT";
    makeBiosBootable = false;
    makeEfiBootable = true;
    makeUsbBootable = true;

    # Upstream only copies this payload when BIOS boot is enabled, although
    # the UEFI GRUB menu also references it.
    contents = [
      {
        source = pkgs.memtest86plus.efi;
        target = "/boot/memtest.bin";
      }
    ];
  };

  # Upstream's hybrid GPT flag only creates partitions alongside its BIOS
  # bootloader. A UEFI-only USB image needs an explicit EFI System Partition.
  system.build.isoImage = lib.mkForce (
    (pkgs.callPackage "${modulesPath}/../lib/make-iso9660-image.nix" {
      inherit (config.isoImage) contents volumeID squashfsCompression compressImage;
      isoName = "${config.image.baseName}.iso";
      squashfsContents = config.isoImage.storeContents;
      syslinux = null;
      efiBootable = true;
      efiBootImage = "boot/efi.img";
    }).overrideAttrs (old: {
      buildCommandPath = pkgs.writeText "make-uefi-only-iso.sh" ''
        set -euo pipefail
        isoBootFlags=""
        usbBootFlags=""
        ${lib.replaceStrings
          ["-isohybrid-gpt-basdat"]
          ["-efi-boot-part --efi-boot-image"]
          (builtins.readFile old.buildCommandPath)}
      '';
    })
  );

  # Keep broad live-media hardware support, but omit offline installer sources
  # and the kernel-specific ZFS stack. Utility man pages remain available.
  system.installer.channel.enable = false;
  nixpkgs.flake = {
    setNixPath = false;
    setFlakeRegistry = false;
  };
  # The installer preloads build tools for offline installations. This image
  # only needs the runtime closure of its diagnostic tools.
  system.extraDependencies = lib.mkForce [];
  programs.git.enable = false;
  installer.cloneConfig = false;
  documentation = {
    nixos.enable = lib.mkForce false;
    doc.enable = false;
    info.enable = false;
    man.enable = true;
  };
  boot.supportedFilesystems.zfs = lib.mkForce false;
  nix.settings = {
    experimental-features = ["nix-command" "flakes"];
    trusted-users = lib.mkForce ["root"];
  };

  users.users = {
    ilma4 = {
      isNormalUser = true;
      initialHashedPassword = "";
      extraGroups = ["wheel" "networkmanager" "video"];
      openssh.authorizedKeys.keys = constants.main-pub-keys;
    };
    # Disable the otherwise passwordless upstream live-media accounts.
    nixos = {
      initialHashedPassword = lib.mkForce "!";
      extraGroups = lib.mkForce [];
    };
    root.initialHashedPassword = lib.mkForce "!";
  };
  security.sudo.wheelNeedsPassword = lib.mkForce false;

  networking.networkmanager.enable = true;
  networking.modemmanager.enable = false;
  services.speechd.enable = false;
  services.openssh = {
    enable = true;
    openFirewall = true;
    settings = {
      AllowUsers = ["ilma4"];
      PermitRootLogin = "no";
      PasswordAuthentication = false;
      KbdInteractiveAuthentication = false;
      PermitEmptyPasswords = false;
    };
  };

  # A console session is also useful when graphics fail. Never start Sway in
  # an SSH session, a terminal emulator, or one of the other virtual consoles.
  services.getty = {
    autologinUser = lib.mkForce "ilma4";
    helpLine = lib.mkForce ''
      Troubleshooting live image: ilma4 has passwordless sudo.
      SSH: ssh ilma4@<IP> (main keys only). Find addresses with ip -br address.
      Wi-Fi: nmtui. Desktop: sway. Help: cat /etc/troubleshooting.txt
    '';
  };
  programs.bash.loginShellInit = ''
    if [[ -z "''${SSH_CONNECTION:-}" && "$(tty)" == /dev/tty1 ]]; then
      sway
    fi
  '';

  programs.sway = {
    enable = true;
    xwayland.enable = false;
    extraPackages = [pkgs.foot pkgs.wmenu];
  };
  fonts = {
    fontconfig.enable = true;
    enableDefaultPackages = false;
    packages = [pkgs.dejavu_fonts];
  };
  environment.etc."sway/config".text = ''
    set $mod Mod4
    set $term ${pkgs.foot}/bin/foot
    set $menu ${pkgs.wmenu}/bin/wmenu-run
    font pango:DejaVu Sans Mono 10
    output * bg #202020 solid_color
    input type:touchpad tap enabled

    bindsym $mod+Return exec $term
    bindsym $mod+d exec $menu
    bindsym $mod+b exec ${pkgs.firefox}/bin/firefox
    bindsym $mod+Shift+q kill
    bindsym $mod+Shift+c reload
    bindsym $mod+Shift+e exit
    bindsym $mod+Left focus left
    bindsym $mod+Down focus down
    bindsym $mod+Up focus up
    bindsym $mod+Right focus right
    bindsym $mod+Shift+Left move left
    bindsym $mod+Shift+Down move down
    bindsym $mod+Shift+Up move up
    bindsym $mod+Shift+Right move right
    bindsym $mod+h splith
    bindsym $mod+v splitv
    bindsym $mod+f fullscreen toggle
    bindsym $mod+Shift+space floating toggle
    floating_modifier $mod normal

    include /etc/sway/config.d/*
    exec $term
  '';

  programs.mtr.enable = true;
  environment.systemPackages = with pkgs; [
    # Storage/recovery tools, Vim, tcpdump, PCI/USB tools and jq are already
    # supplied by the minimal ISO profile; filesystem modules add their tools.
    firefox
    lvm2
    mdadm
    dmidecode
    lm_sensors
    memtester
    stress-ng
    ethtool
    nmap
    iperf3
    dnsutils
    curl
    wget
    htop
    iotop
    sysstat
    strace
    lsof
    ripgrep
  ];

  environment.etc."troubleshooting.txt".text = ''
    NixOS troubleshooting live image (UEFI, x86_64)

    Super+Return: terminal    Super+d: launcher    Super+b: Firefox
    Super+Shift+q: close      Super+f: fullscreen  Super+Shift+e: exit Sway
    Ctrl+Alt+F2: console      sway: start the desktop again

    Network: ip -br address; nmcli; nmtui
    SSH: ssh ilma4@<IP>, using either main key from constants.nix
    Root privileges: sudo <command> (no password)
    Logs: journalctl -b; journalctl -k -b; systemctl --failed
    Disks: lsblk -f; sudo smartctl --scan; sudo nvme list

    This is an ephemeral live system. Save logs and recovered data to another
    device before rebooting. Disks are not automatically mounted for recovery.
    Full Nixpkgs sources are not bundled; extra Nix packages need networking.
  '';

  system.stateVersion = "26.05";
}
