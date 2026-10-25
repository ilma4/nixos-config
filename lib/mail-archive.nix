{
  lib,
  constants,
}: let
  archive = constants.mail-archive;
  accounts = {
    gmail = {host = "imap.gmail.com";};
    yandex = {host = "imap.ya.ru";};
    proton = {host = "127.0.0.1";};
  };
in {
  notmuchConfig = ''
    [database]
    path=${archive.index}
    mail_root=${archive.mailRoot}

    [new]
    tags=archive;
    ignore=/(^|/)([.]mbsync[^/]*|[.]uidvalidity|[.]isyncuidmap[.]db|dovecot[^/]*|subscriptions)$/;

    [maildir]
    synchronize_flags=false
  '';

  mbsyncConfig =
    lib.concatMapStringsSep "\n" (name: let
      proton = name == "proton";
    in ''
      IMAPAccount ${name}
      Host ${accounts.${name}.host}
      Port ${
        if proton
        then "1143"
        else "993"
      }
      UserCmd "cat ${archive.secretDir}/mail-${name}-user"
      PassCmd "cat ${archive.secretDir}/mail-${name}"
      TLSType ${
        if proton
        then "None"
        else "IMAPS"
      }
      ${lib.optionalString proton "AuthMechs PLAIN"}

      IMAPStore ${name}-remote
      Account ${name}

      MaildirStore ${name}-local
      Path ${archive.mailRoot}/${name}/
      Inbox ${archive.mailRoot}/${name}/INBOX
      SubFolders Verbatim

      Channel ${name}
      Far :${name}-remote:
      Near :${name}-local:
      Patterns *
      Sync PullNew
      Create Near
      Remove None
      Expunge None
      CopyArrivalDate yes
      SyncState *
    '')
    archive.accounts;

  indexScript = ''
    set -euo pipefail
    exec flock ${archive.home}/index.lock \
      notmuch --config=${archive.configDir}/notmuch-config new
  '';

  syncScript = ''
    set -euo pipefail
    sync_status=0
    mbsync -c ${archive.configDir}/mbsyncrc -a || sync_status=$?

    index_status=0
    flock ${archive.home}/index.lock \
      notmuch --config=${archive.configDir}/notmuch-config new || index_status=$?

    if [ "$sync_status" -ne 0 ]; then
      exit "$sync_status"
    fi
    exit "$index_status"
  '';
}
