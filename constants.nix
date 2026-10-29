{
  # How to add a new key: docs/new-main-ssh-key.md
  main-pub-keys = [
    # quicksilver secretive 'main-key'
    "ecdsa-sha2-nistp256 AAAAE2VjZHNhLXNoYTItbmlzdHAyNTYAAAAIbmlzdHAyNTYAAABBBC53cFbtJbKNxzktt68EAli91ithRY2IvgunmYPpe6RXDLLzRs4iFjJKnZqrCBxwC54rrXKto8JqWokFISYvmgU= ilya.malakhov4@gmail.com"

    # Bitwarden 'main-key'
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIFdYWQA91YiviGcsXEVUf4/dbAU2So1AAa1qU6ZFlx7A"
  ];
  github-pub-keys = [
    # quicksilver secretive 'github-key'
    "ecdsa-sha2-nistp256 AAAAE2VjZHNhLXNoYTItbmlzdHAyNTYAAAAIbmlzdHAyNTYAAABBBIpJ1f6e1rMESqF6VyzQa1NYAVFgKXV5Kx8sJbr91T5uVMo0CErJfmuYMYwENxEIXhMlqXLyqGIcN6MUl03qKzk= ilya.malakhov4@gmail.com"

    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIM/LF/1Qn7CPiHRcfdo532DOb22vG66YGhYHF9x1Fph7"
  ];

  ios-pub-key = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOKaUONhI8X/55/+nNWKvFdvQlGcipI+WUGY/OuveceC ios-key";

  telegram = {
    my-id-secret = "telegram/my_id";
    mallard = {
      api-key-secret = "telegram/mallard/api_key";
    };
  };

  ntfy = rec {
    host = "ntfy.ilma4.home.arpa";
    port = 2586;
    base-url = "https://${host}";
    local-base-url = "http://127.0.0.1:${toString port}";
    topic = "notifications";
  };

  mail-archive = {
    uid = 807;
    gid = 807;
    home = "/var/lib/mail-archive";
    mailRoot = "/srv/mail";
    index = "/var/lib/mail-index";
    configDir = "/etc/mail-archive";
    secretDir = "/run/secrets";
    accounts = ["gmail" "yandex" "proton"];
    cypht = {
      host = "cypht.ilma4.home.arpa";
      port = 8088;
      proxyGateway = "10.20.0.1";
      data = "/srv/cypht";
    };
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
    hostname = "DE-UNIT-1832";
    # Existing key used to send Quicksilver backups to NAS.
    backup-pub-key = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIMvrzYraYfx9T5iQOrsU19YvfdgUCZlANxdSjJTKaRBR qucksilver-backup-key";
  };

  backup-ssh-keys = {
    nas-to-hetzer-storage = {
      private-secret = "backup_ssh/nas_to_hetzer_storage/private_key";
      public-secret = "backup_ssh/nas_to_hetzer_storage/public_key";
    };
  };

  nas = {
    lan-ip = "192.168.1.33";
    pihole = {
      lan-ip = "192.168.1.200";
      host-subnet = "10.78.0.0/30";
      host-gateway = "10.78.0.1";
      host-ip = "10.78.0.2";
    };

    # Stable source address for the qBittorrent WebUI's trusted proxy path.
    traefik-ip = "10.20.0.2";

    # for personal backups
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
    # for servers data backup
    restic-server = {
      repo = "/mnt/hdd/restic";
      password-file = "restic/server";
      old-password-file = null; # used to migrate password on repo
    };
  };
}
