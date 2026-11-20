{
  config,
  constants,
  ...
}: let
  user = constants.msi-modern-builder-user;
in {
  users.groups.${user} = {};
  users.users.${user} = {
    isSystemUser = true;
    group = user;
    useDefaultShell = true;
    openssh.authorizedKeys.keys = [
      ''restrict,from="${constants.nas.lan-ip}",command="${config.nix.package}/bin/nix-daemon --stdio" ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAID+A+DQl1YNwq2WbbUulHHaUzFZ5fOtDd3wGtGk9P3BX nas-to-msi-modern-nix-builder''
    ];
  };

  # Trusted Nix clients are effectively root; only the NAS's dedicated LAN key
  # can SSH as this account, and it can only start the Nix daemon protocol.
  nix.settings.trusted-users = [user];
}
