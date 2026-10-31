{
  pkgs,
  constants,
}: let
  inherit (pkgs) lib;
  archiveFiles = import ../lib/mail-archive.nix {inherit lib constants;};
  upstreamConfig = pkgs.writeText "mail-archive-fixture-imap.conf" ''
    dovecot_config_version = 2.4.0
    dovecot_storage_version = 2.4.0
    base_dir = /run/fixture-imap
    state_dir = /var/lib/fixture-imap
    default_internal_user = dovecot2
    default_internal_group = dovecot2
    default_login_user = dovenull
    protocols {
      imap = yes
    }
    listen = 127.0.0.1
    ssl = no
    auth_allow_cleartext = yes
    auth_mechanisms = plain
    first_valid_uid = 807
    mail_driver = maildir
    mail_path = /var/lib/upstream/%{user}
    mail_inbox_path = /var/lib/upstream/%{user}/INBOX
    mailbox_list_layout = fs
    namespace inbox {
      inbox = yes
      separator = /
    }
    passdb passwd-file {
      passwd_file_path = /run/fixture-users
    }
    userdb static {
      fields {
        uid = mailstore
        gid = mailstore
        home = /var/lib/upstream/%{user}
      }
    }
    service imap-login {
      inet_listener imap {
        port = 1193
      }
      inet_listener imaps {
        port = 0
      }
    }
  '';
in
  pkgs.testers.runNixOSTest {
    name = "mail-archive";
    node.specialArgs = {inherit constants;};
    nodes.archive = {...}: {
      imports = [../modules/mail-archive.nix];
      environment.systemPackages = [pkgs.python3];
      virtualisation.memorySize = 3072;
      virtualisation.cores = 2;
      systemd.timers.mail-archive-index.enable = false;
      i4.mailArchive.passwordFile = "/run/archive-test-users";
      environment.etc."mail-archive/mbsyncrc".text = lib.mkForce (lib.replaceStrings
        ["imap.gmail.com" "imap.ya.ru" "Port 993" "Port 1143" "TLSType IMAPS"]
        ["127.0.0.1" "127.0.0.1" "Port 1193" "Port 1193" "TLSType None\nAuthMechs PLAIN"]
        archiveFiles.mbsyncConfig);
      systemd.services.mail-archive-sync.wants = lib.mkForce ["network-online.target"];
      systemd.services.fixture-imap = {
        serviceConfig = {
          ExecStart = "${pkgs.dovecot}/bin/dovecot -F -c ${upstreamConfig}";
          RuntimeDirectory = "fixture-imap";
        };
      };
      systemd.tmpfiles.rules = [
        "f /run/archive-test-users 0640 root dovecot2 -"
        "d /var/lib/upstream 0700 mailstore mailstore -"
        "d /var/lib/fixture-imap 0700 root root -"
      ];
      containers.reader = {
        autoStart = false;
        ephemeral = true;
        privateNetwork = true;
        # Isolate root's capabilities while keeping the bind mounts' host IDs.
        privateUsers = "identity";
        bindMounts = lib.genAttrs [constants.mail-archive.mailRoot constants.mail-archive.index] (path: {
          hostPath = path;
          isReadOnly = true;
        });
        config = {
          networking.hostName = "reader";
          # Bind mounts retain host ownership; UID translation remains specific
          # to the production VM's virtiofs exports.
          users.groups.mailstore.gid = constants.mail-archive.gid;
          users.users.ilma4 = {
            isSystemUser = true;
            uid = constants.mail-archive.uid;
            group = "mailstore";
          };
          environment.systemPackages = [pkgs.notmuch];
          environment.etc."mail-archive/notmuch-config".text = archiveFiles.notmuchConfig;
          system.stateVersion = "26.05";
        };
      };
      systemd.services."container@reader" = {
        after = ["mail-archive-index.service"];
        requires = ["mail-archive-index.service"];
      };
    };
    testScript = builtins.readFile ./mail-archive.py;
  }
