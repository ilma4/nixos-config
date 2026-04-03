{
  config,
  pkgs,
  lib,
  ...
}: {
  virtualisation.incus.enable = true;
  networking.nftables.enable = true;

  users.users.ilma4.extraGroups = ["incus-admin"];

  # If your Incus bridge is incusbr0, either trust it:
  networking.firewall.trustedInterfaces = ["incusbr0"];
}
