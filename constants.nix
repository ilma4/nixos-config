{
  main-pub-keys = [
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIFdYWQA91YiviGcsXEVUf4/dbAU2So1AAa1qU6ZFlx7A"
  ];
  github-pub-key = "TODO";

  telegram = {
    my-id-secret = "telegram/my_id";
    mallard = {
      api-key-secret = "telegram/mallard/api_key";
    };
    notifications-api-key-secret = "telegram/notifications_api_key";
  };

  hetzer-restic = rec {
    repo = "/home/restic";
    password-secret = "restic_password/hetzer_storage_box";
    password-file = "/run/secrets/${password-secret}";
    old-password-secret = null;
    old-password-file =
      if old-password-secret == null
      then null
      else "/run/secrets/${old-password-secret}";
  };

  quicksilver = {
    # public ssh key to send backups to remote machines
    backup-pub-key = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIMvrzYraYfx9T5iQOrsU19YvfdgUCZlANxdSjJTKaRBR qucksilver-backup-key";
  };

  nas = {
    restic-ilma4 = rec {
      location = "/mnt/hdd/restic";
      password-secret = "restic_password/ilma4_legacy";
      password-file = "/run/secrets/${password-secret}";
      old-password-secret = null; # used to migrate passwod on repo
      old-password-file =
        if old-password-secret == null
        then null
        else "/run/secrets/${old-password-secret}";
    };
    restic = {
      repo = "/mnt/hdd/restic";
      password-file = "restic/server";
      old-password-file = null; # used to migrate password on repo
    };
  };
}
