{
  config,
  inputs,
  lib,
  modulesPath,
  ...
}: {
  imports = [
    inputs.home-manager.nixosModules.home-manager
    ../../modules/base.nix
    "${modulesPath}/virtualisation/lxc-container.nix"
    "${modulesPath}/virtualisation/lxc-image-metadata.nix"
  ];

  i4.home-manager.enable = false;

  networking = {
    hostName = "openclaw";
    dhcpcd.enable = false;
    useDHCP = false;
    useHostResolvConf = false;
  };

  systemd.network = {
    enable = true;
    networks."50-eth0" = {
      matchConfig.Name = "eth0";
      networkConfig = {
        DHCP = "ipv4";
        IPv6AcceptRA = true;
      };
      linkConfig.RequiredForOnline = "routable";
    };
  };

  services.getty.helpLine = lib.mkForce "";
  services.openssh.settings.PermitRootLogin = lib.mkForce "no";
  services.tailscale.enable = false;

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
