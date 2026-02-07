{
  main-pub-key = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIFdYWQA91YiviGcsXEVUf4/dbAU2So1AAa1qU6ZFlx7A";
  github-pub-key = "TODO";

  hetzer-restic = {
    repo = "/home/restic";
    password-file = "TODO";
    old-password-file = null;
  };

  laat = {
    restic = {
      repo = "/mnt/hdd/restic";
      password-file = "/run/secrets/..."; # TODO
      old-password-file = null; # used to update password on repo
    };
  };
}
