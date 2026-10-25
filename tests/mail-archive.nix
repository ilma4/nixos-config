{
  pkgs,
  inputs,
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
    nodes.archive = {config, ...}: {
      imports = [../modules/mail-archive.nix inputs.microvm.nixosModules.host];
      environment.systemPackages = [pkgs.python3 pkgs.openssh pkgs.sshpass];
      virtualisation.memorySize = 3072;
      virtualisation.cores = 2;
      microvm.autostart = lib.mkForce [];
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
      microvm.vms.reader.config = {
        imports = [inputs.microvm.nixosModules.microvm ../hosts/openclaw/mail-archive.nix];
        _module.args.constants = constants;
        networking.hostName = "reader";
        networking.useDHCP = true;
        users.users.ilma4 = {
          isNormalUser = true;
          uid = 1000;
        };
        # Test-only password, never part of either real host's configuration.
        users.users.root.initialPassword = "fixture";
        services.openssh = {
          enable = true;
          settings = {
            PermitRootLogin = "yes";
            PasswordAuthentication = true;
          };
        };
        microvm = {
          hypervisor = "qemu";
          cpu = "max";
          vcpu = 1;
          mem = 512;
          writableStoreOverlay = "/nix/.rw-store";
          interfaces = [
            {
              type = "user";
              id = "eth0";
              mac = "02:00:00:00:00:01";
            }
          ];
          forwardPorts = [
            {
              host.address = "127.0.0.1";
              host.port = 2222;
              guest.port = 22;
            }
          ];
          shares = [
            {
              proto = "virtiofs";
              tag = "ro-store";
              source = "/nix/store";
              mountPoint = "/nix/.ro-store";
              readOnly = true;
            }
          ];
        };
        system.stateVersion = "26.05";
      };
      systemd.services."microvm@reader".wantedBy = lib.mkForce [];
      systemd.services."microvm-virtiofsd@reader" = {
        after = ["mail-archive-index.service"];
        requires = ["mail-archive-index.service"];
      };
    };
    testScript = builtins.readFile ./mail-archive.py;
  }
