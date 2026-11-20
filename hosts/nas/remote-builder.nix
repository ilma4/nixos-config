{
  config,
  constants,
  ...
}: let
  host = "msi-modern.local";
  key = "nas-msi-modern-builder-ssh-key";
in {
  sops.secrets.${key} = {};

  # Keep the NAS's local build slots for when the laptop is offline.
  nix = {
    distributedBuilds = true;
    settings.builders-use-substitutes = true;
    buildMachines = [
      {
        hostName = host;
        protocol = "ssh-ng";
        sshUser = constants.msi-modern-builder-user;
        sshKey = config.sops.secrets.${key}.path;
        system = "x86_64-linux";
        maxJobs = 2;
        supportedFeatures = ["benchmark" "big-parallel" "kvm" "nixos-test"];
      }
    ];
  };

  programs.ssh = {
    knownHosts.${host}.publicKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIGFHSSO6t04no626YFiUiacMOHA7Yu33G7KsJVjXtd/b";
    extraConfig = ''
      Host ${host}
        AddressFamily inet
        BindInterface enp2s0
        BatchMode yes
        ConnectTimeout 3
        IdentitiesOnly yes
        StrictHostKeyChecking yes
        UserKnownHostsFile /dev/null
    '';
  };
}
