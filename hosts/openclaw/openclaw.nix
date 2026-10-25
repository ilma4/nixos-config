{
  inputs,
  lib,
  ...
}: {
  imports = [
    inputs.home-manager.nixosModules.home-manager
    ../../modules/base.nix
    inputs.microvm.nixosModules.microvm
  ];

  home-manager.users.ilma4 = import ./home.nix;
  # Preserve files created before Home Manager takes ownership of the home.
  home-manager.backupFileExtension = "before-home-manager";
  # Store optimisation cannot operate across the read-only host store overlay.
  nix.optimise.automatic = lib.mkForce false;
  hardware.enableAllFirmware = false;

  boot.kernelParams = ["net.ifnames=0"];
  microvm = {
    hypervisor = "qemu";
    vcpu = 2;
    mem = 2049;
    balloon = true;
    interfaces = [
      {
        type = "tap";
        id = "openclaw-tap";
        mac = "02:00:00:77:00:02";
        tap.vhost = true;
      }
    ];
    volumes = [
      {
        image = "state.img";
        mountPoint = "/";
        size = 20480;
      }
    ];
    shares = [
      {
        proto = "virtiofs";
        tag = "ro-store";
        source = "/nix/store";
        mountPoint = "/nix/.ro-store";
        readOnly = true;
      }
    ];
    writableStoreOverlay = "/nix/.rw-store";
  };

  networking = {
    hostName = "openclaw";
    dhcpcd.enable = false;
    useDHCP = false;
    useNetworkd = true;
    useHostResolvConf = false;
    interfaces.eth0.ipv4.addresses = [
      {
        address = "10.77.0.2";
        prefixLength = 30;
      }
    ];
    defaultGateway = {
      address = "10.77.0.1";
      interface = "eth0";
    };
    nameservers = ["1.1.1.1" "8.8.8.8"];
  };

  services.getty.helpLine = lib.mkForce "";
  services.fwupd.enable = false;
  services.printing.enable = false;
  services.smartd.enable = false;
  services.openssh.settings.PermitRootLogin = lib.mkForce "no";
  services.tailscale.enable = false;
  security.rtkit.enable = false;

  users.users.root.initialHashedPassword = lib.mkForce "!";

  security.sudo.extraRules = [
    {
      users = ["ilma4"];
      commands = [
        {
          command = "ALL";
          options = ["NOPASSWD"];
        }
      ];
    }
  ];

  system.stateVersion = "25.11";
}
