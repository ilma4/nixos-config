{
  config,
  constants,
  lib,
  pkgs,
  ...
}: let
  archive = constants.mail-archive;
  cfg = config.i4.mailArchive;
  files = import ../lib/mail-archive.nix {inherit constants lib;};
  serviceDefaults = {
    Type = "oneshot";
    User = "mailstore";
    Group = "mailstore";
    WorkingDirectory = archive.home;
    UMask = "0077";
    NoNewPrivileges = true;
    ProtectSystem = "strict";
    ProtectHome = true;
    PrivateTmp = true;
    ReadWritePaths = [archive.home archive.mailRoot archive.index];
  };
in {
  options.i4.mailArchive = {
    sync.enable = lib.mkEnableOption "provider downloads (requires credentials and Proton onboarding)";
    passwordFile = lib.mkOption {
      type = lib.types.path;
      default = pkgs.writeText "mail-archive-no-users" "";
      description = "Dovecot passwd-file; the default rejects every login. Set to a runtime sops secret during onboarding.";
    };
  };

  config = {
    users.users.mailstore = {
      isSystemUser = true;
      uid = archive.uid;
      group = "mailstore";
      home = archive.home;
    };
    users.groups.mailstore.gid = archive.gid;

    environment.systemPackages = [pkgs.hydroxide pkgs.isync pkgs.notmuch pkgs.dovecot];
    environment.etc = {
      "mail-archive/mbsyncrc".text = files.mbsyncConfig;
      "mail-archive/notmuch-config".text = files.notmuchConfig;
      "dovecot/archive-users".source = cfg.passwordFile;
    };

    systemd.tmpfiles.rules = map (path: "d ${path} 0700 mailstore mailstore -") (
      [archive.home archive.mailRoot archive.index]
      ++ lib.concatMap (name: [
        "${archive.home}/${name}"
        "${archive.mailRoot}/${name}"
        "${archive.mailRoot}/${name}/INBOX"
        "${archive.mailRoot}/${name}/INBOX/cur"
        "${archive.mailRoot}/${name}/INBOX/new"
        "${archive.mailRoot}/${name}/INBOX/tmp"
      ])
      archive.accounts
    );

    services.dovecot2 = {
      enable = true;
      package = pkgs.dovecot;
      enablePAM = false;
      createMailUser = false;
      settings = {
        dovecot_config_version = "2.4.0";
        dovecot_storage_version = "2.4.0";
        protocols.imap = true;
        listen = "127.0.0.1";
        ssl = "no";
        auth_allow_cleartext = true;
        auth_mechanisms = ["plain"];
        first_valid_uid = archive.uid;
        mail_uid = "mailstore";
        mail_gid = "mailstore";
        mail_driver = "maildir";
        mail_path = "${archive.mailRoot}/%{user}";
        mail_inbox_path = "${archive.mailRoot}/%{user}/INBOX";
        mailbox_list_layout = "fs";
        "namespace inbox" = {
          inbox = true;
          separator = "/";
        };
        "passdb passwd-file".passwd_file_path = "/etc/dovecot/archive-users";
        "userdb static".fields = {
          uid = "mailstore";
          gid = "mailstore";
          home = "${archive.home}/%{user}";
        };
        "service imap-login" = {
          "inet_listener imap".port = 1144;
          "inet_listener imaps".port = 0;
        };
      };
    };

    systemd.services = {
      mail-archive-hydroxide = {
        description = "Proton Mail archive IMAP bridge";
        wantedBy = lib.optionals cfg.sync.enable ["multi-user.target"];
        after = ["network-online.target" "systemd-tmpfiles-setup.service"];
        wants = ["network-online.target"];
        environment.HOME = archive.home;
        serviceConfig =
          serviceDefaults
          // {
            Type = "simple";
            ExecStart = "${pkgs.hydroxide}/bin/hydroxide -imap-host 127.0.0.1 -imap-port 1143 imap";
            Restart = "on-failure";
            RestartSec = 10;
          };
      };
      mail-archive-index = {
        description = "Index the local mail archive";
        wantedBy = ["multi-user.target"];
        after = ["systemd-tmpfiles-setup.service"];
        environment.HOME = archive.home;
        path = [pkgs.notmuch pkgs.util-linux];
        script = files.indexScript;
        serviceConfig = serviceDefaults;
      };
      mail-archive-sync = {
        description = "Download new mail and index successful downloads";
        after = ["network-online.target" "mail-archive-hydroxide.service"];
        wants = ["network-online.target" "mail-archive-hydroxide.service"];
        unitConfig.ConditionPathExists =
          lib.concatMap (name: [
            "${archive.secretDir}/mail-${name}-user"
            "${archive.secretDir}/mail-${name}"
          ])
          archive.accounts;
        environment.HOME = archive.home;
        path = [pkgs.coreutils pkgs.isync pkgs.notmuch pkgs.util-linux];
        script = files.syncScript;
        serviceConfig = serviceDefaults;
      };
    };
    systemd.timers = {
      mail-archive-index = {
        wantedBy = ["timers.target"];
        timerConfig = {
          OnBootSec = "2min";
          OnUnitInactiveSec = "2min";
        };
      };
      mail-archive-sync = {
        wantedBy = lib.optionals cfg.sync.enable ["timers.target"];
        timerConfig = {
          OnBootSec = "2min";
          OnUnitInactiveSec = "2min";
        };
      };
    };
  };
}
