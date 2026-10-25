import base64
import json
import shlex
from email.message import EmailMessage

start_all()
archive.wait_for_unit("multi-user.target")
archive.succeed("systemctl start mail-archive-index.service")
archive.succeed("doveconf -n")
archive.succeed("doveadm pw -l | grep -w ARGON2ID")
archive.fail("doveadm auth test gmail anything")
archive.succeed("test ! -e /etc/systemd/system/timers.target.wants/mail-archive-sync.timer")
archive.succeed("test ! -e /etc/systemd/system/multi-user.target.wants/mail-archive-hydroxide.service")


def put(path, content, owner="mailstore:mailstore", mode="600"):
    encoded = base64.b64encode(content.encode()).decode()
    archive.succeed(
        f"mkdir -p {shlex.quote(path.rsplit('/', 1)[0])}; "
        f"echo {encoded} | base64 -d > {shlex.quote(path)}; "
        f"chown {owner} {shlex.quote(path)}; chmod {mode} {shlex.quote(path)}"
    )


def python(code):
    return archive.succeed("python3 -c " + shlex.quote(code))


for provider in ["gmail", "yandex", "proton"]:
    root = f"/var/lib/upstream/{provider}"
    archive.succeed(f"mkdir -p {root}/INBOX/{{cur,new,tmp}}; chown -R mailstore:mailstore {root}")
    put(f"/run/secrets/mail-{provider}-user", provider)
    put(f"/run/secrets/mail-{provider}", "wrong" if provider == "yandex" else "fixture")
    message = EmailMessage()
    message["From"] = "sender@example.invalid"
    message["To"] = f"{provider}@example.invalid"
    message["Subject"] = f"Invoice {provider}"
    message["Message-ID"] = f"<{provider}@archive-fixture.invalid>"
    message["Date"] = "Sun, 25 Oct 2026 10:00:00 +0100"
    message.set_content(f"Archive fixture body for {provider}.")
    message.add_attachment(b"fixture-attachment", maintype="application", subtype="octet-stream", filename="invoice.bin")
    put(f"{root}/INBOX/new/fixture", message.as_string())

put("/run/fixture-users", "".join(f"{p}:{{PLAIN}}fixture\n" for p in ["gmail", "yandex", "proton"]), "root:dovecot2", "640")
archive.succeed("systemctl start fixture-imap")
archive.wait_for_open_port(1193)

with subtest("partial failure still downloads and indexes the other accounts"):
    archive.fail("systemctl start mail-archive-sync")
    assert archive.succeed("sudo -u mailstore notmuch --config=/etc/mail-archive/notmuch-config count '*'").strip() == "2"
    result = python("""
import imaplib
c = imaplib.IMAP4('127.0.0.1', 1193)
c.login('gmail', 'fixture')
c.select('INBOX')
assert b'\\\\Seen' not in c.fetch('1', '(FLAGS)')[1][0]
c.logout()
""")

put("/run/secrets/mail-yandex", "fixture")
archive.succeed("systemctl reset-failed mail-archive-sync; systemctl start mail-archive-sync")
assert archive.succeed("sudo -u mailstore notmuch --config=/etc/mail-archive/notmuch-config count '*'").strip() == "3"

with subtest("guest reads private messages and attachments but cannot write"):
    archive.succeed("systemctl start microvm@reader")
    ssh = "sshpass -p fixture ssh -p 2222 -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=5 root@127.0.0.1 "
    archive.wait_until_succeeds(ssh + "true", timeout=300)

    def guest(command, fails=False):
        return (archive.fail if fails else archive.succeed)(ssh + shlex.quote(command))

    assert guest("stat -c '%u:%g:%a' /srv/mail").strip() == "1000:100:700"
    assert guest("stat -c '%u:%g:%a' /var/lib/mail-index").strip() == "1000:100:700"
    query = "notmuch --config=/etc/mail-archive/notmuch-config"
    raw = guest("su -s /bin/sh ilma4 -c " + shlex.quote(query + " search --format=json '*'"))
    assert len(json.loads(raw)) == 3
    raw = guest("su -s /bin/sh ilma4 -c " + shlex.quote(query + " show --format=json 'id:proton@archive-fixture.invalid'"))
    assert "invoice.bin" in raw
    assert "Archive fixture body for proton" in raw
    raw = guest("su -s /bin/sh ilma4 -c " + shlex.quote(query + " show --format=raw --part=3 'id:proton@archive-fixture.invalid'"))
    assert raw == "fixture-attachment"
    guest("touch /srv/mail/guest-write", fails=True)
    guest("touch /var/lib/mail-index/guest-write", fails=True)
    guest("mount -o remount,rw /srv/mail || true; touch /srv/mail/remount-write", fails=True)
    guest(query + " tag +changed '*'", fails=True)
    guest(query + " new", fails=True)
    guest("test ! -e /run/secrets/mail-gmail; test ! -e /var/lib/mail-archive; test ! -S /run/podman/podman.sock")
    archive.succeed("test ! -e /srv/mail/guest-write; test ! -e /srv/mail/remount-write")

with subtest("upstream deletion keeps the downloaded copy"):
    python(r"""
import imaplib
c = imaplib.IMAP4('127.0.0.1', 1193)
c.login('gmail', 'fixture')
c.select('INBOX')
c.store('1', '+FLAGS', r'(\Deleted)')
c.expunge()
c.logout()
""")
    archive.succeed("systemctl start mail-archive-sync")
    assert archive.succeed("sudo -u mailstore notmuch --config=/etc/mail-archive/notmuch-config count 'id:gmail@archive-fixture.invalid'").strip() == "1"

with subtest("local read move and delete never affect the upstream account"):
    put("/run/archive-test-users", "yandex:{PLAIN}local-fixture\n", "root:dovecot2", "640")
    archive.succeed("doveadm auth cache flush")
    python(r"""
import imaplib
c = imaplib.IMAP4('127.0.0.1', 1144)
c.login('yandex', 'local-fixture')
c.select('INBOX')
assert c.fetch('1', '(BODY[])')[0] == 'OK'
assert c.create('LocalMoved')[0] == 'OK'
assert c.copy('1', 'LocalMoved')[0] == 'OK'
c.store('1', '+FLAGS', r'(\Deleted)')
c.expunge()
c.select('LocalMoved')
c.store('1', '+FLAGS', r'(\Deleted)')
c.expunge()
c.logout()
""")
    # Patterns * also sees local-only folders. The guide's Create Near policy
    # must report that LocalMoved has no upstream counterpart, never create it
    # upstream, and still index the local deletion.
    archive.fail("systemctl start mail-archive-sync")
    python("""
import imaplib
c = imaplib.IMAP4('127.0.0.1', 1193)
c.login('yandex', 'fixture')
assert c.select('INBOX')[1] == [b'1']
assert b'\\\\Seen' not in c.fetch('1', '(FLAGS)')[1][0]
assert 'LocalMoved' not in repr(c.list()[1])
c.logout()
""")
    assert archive.succeed("sudo -u mailstore notmuch --config=/etc/mail-archive/notmuch-config count 'id:yandex@archive-fixture.invalid'").strip() == "0"
