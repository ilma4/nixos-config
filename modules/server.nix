{
  config,
  lib,
  ...
}: {
  virtualisation.podman = {
    enable = true;
    dockerCompat = true; # create alias docker=podman
    autoPrune.enable = true;
    defaultNetwork.settings = {
      # Required for container networking to be able to use names.
      dns_enabled = true;
    };
  };

  # Enable container name DNS for non-default Podman networks.
  # NixOS already opens DNS for the default podman0 bridge when dns_enabled = true;
  # custom networks need an additional rule for their generated podman* bridges.
  networking.firewall = lib.mkMerge [
    (lib.mkIf (config.networking.firewall.backend == "nftables") {
      extraInputRules = ''
        iifname "podman*" udp dport 53 accept comment "allow Podman network DNS"
      '';
    })
    (lib.mkIf (config.networking.firewall.backend == "iptables") {
      # iptables uses a trailing + to match an interface-name prefix.
      interfaces."podman+".allowedUDPPorts = [53];
    })
  ];

  virtualisation.oci-containers.backend = "podman";

  systemd.tmpfiles.rules = [
    "d /srv/ 0751 root root -"
  ];

  /*
  networking.firewall.allowedTCPPorts = [
    443 # https for tailscale serve
  ];
  */
}
