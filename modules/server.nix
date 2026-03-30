{...}: {
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
  # https://github.com/NixOS/nixpkgs/issues/226365
  networking.firewall.interfaces."podman+".allowedUDPPorts = [53];

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
