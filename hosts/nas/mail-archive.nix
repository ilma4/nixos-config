{constants, ...}: {
  imports = [../../modules/mail-archive.nix ./docker-services/cypht.nix];

  # Maildirs and Cypht settings are already covered by the existing /srv backup.
  i4.backup.paths = [constants.mail-archive.home];

  # virtiofsd must find its sources even on a first boot with an empty archive.
  systemd.services."microvm-virtiofsd@openclaw" = {
    after = ["mail-archive-index.service"];
    requires = ["mail-archive-index.service"];
    unitConfig.RequiresMountsFor = [
      constants.mail-archive.mailRoot
      constants.mail-archive.index
    ];
  };
}
