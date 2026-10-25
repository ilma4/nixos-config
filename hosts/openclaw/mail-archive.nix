{
  config,
  constants,
  lib,
  pkgs,
  ...
}: let
  archive = constants.mail-archive;
  files = import ../../lib/mail-archive.nix {inherit constants lib;};
in {
  environment.systemPackages = [pkgs.notmuch];
  environment.etc."mail-archive/notmuch-config".text = files.notmuchConfig;

  # Translate only on these private exports. --readonly is enforced by the host
  # virtiofsd as well as the guest mount, including for guest root.
  microvm.shares = map (share:
    share
    // {
      proto = "virtiofs";
      readOnly = true;
      cache = "never";
      posixAcl = false;
      extraArgs = [
        "--translate-uid"
        "map:${toString config.users.users.ilma4.uid}:${toString archive.uid}:1"
        "--translate-gid"
        "map:${toString config.users.groups.users.gid}:${toString archive.gid}:1"
      ];
    }) [
    {
      tag = "mail-archive";
      source = archive.mailRoot;
      mountPoint = archive.mailRoot;
    }
    {
      tag = "mail-index";
      source = archive.index;
      mountPoint = archive.index;
    }
  ];
}
