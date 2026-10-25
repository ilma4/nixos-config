"""Smoke-test the evaluated production Compose file with disposable storage.

Run as root on a Linux builder with Python/PyYAML and Podman. No ports are
published: the image runs in an isolated network namespace without upstream
IMAP. Only the bridge listen directive is removed from the real nginx config.
"""

import argparse
from html.parser import HTMLParser
import os
from pathlib import Path
import re
import subprocess
import tempfile
import time
import urllib.parse

import yaml


class LoginForm(HTMLParser):
    def __init__(self):
        super().__init__()
        self.fields = {}
        self.passwords = []

    def handle_starttag(self, tag, attrs):
        fields = dict(attrs)
        if tag == "input" and fields.get("name"):
            self.fields[fields["name"]] = fields.get("value", "")
            if fields.get("type") == "password":
                self.passwords.append(fields["name"])


parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("compose", type=Path)
args = parser.parse_args()
assert os.geteuid() == 0, "Run as root so disposable files can use the image's UID 33."
service = yaml.safe_load(args.compose.read_text())["services"]["cypht"]
environment = service["environment"]
assert environment["AUTH_TYPE"] == "IMAP"
assert environment["DEFAULT_SMTP_SERVER"] == ""
nginx_volume = next(v for v in service["volumes"] if ":/etc/nginx/nginx.conf:" in v)
nginx_source = Path(nginx_volume.split(":", 1)[0])
container = f"mail-archive-smoke-{os.getpid()}"


def run(*command, check=True):
    return subprocess.run(command, text=True, capture_output=True, check=check)


with tempfile.TemporaryDirectory(prefix="mail-archive-cypht-") as temporary:
    root = Path(temporary)
    data = root / "data"
    for directory in [data, data / "db", data / "users", data / "attachments"]:
        directory.mkdir(mode=0o700)
        os.chown(directory, 33, 33)
    database = data / "db" / "cypht.sqlite"
    database.touch(mode=0o600)
    os.chown(database, 33, 33)
    nginx = root / "nginx.conf"
    nginx.write_text(re.sub(
        r"(?m)^\s*listen (?!127\.0\.0\.1:)[0-9.]+:[0-9]+;\n", "", nginx_source.read_text()
    ))
    command = ["podman", "run", "--detach", "--name", container, "--network", "none",
               "--volume", f"{data}:/var/lib/hm3", "--volume", f"{nginx}:/etc/nginx/nginx.conf:ro"]
    for volume in service["volumes"]:
        source, target, *mode = volume.split(":")
        if target not in ["/var/lib/hm3", "/etc/nginx/nginx.conf"]:
            assert mode == ["ro"], "Additional configuration mounts must be read-only"
            command.extend(["--volume", volume])
    for key, value in environment.items():
        command.extend(["--env", f"{key}={value}"])
    command.append(service["image"])
    try:
        result = run(*command)
        print("Started isolated container", result.stdout.strip())
        health = service["healthcheck"]["test"][1:]
        for attempt in range(90):
            result = run("podman", "exec", container, *health, check=False)
            if result.returncode == 0:
                break
            time.sleep(1)
        else:
            raise AssertionError("Cypht did not become healthy")
        page = run("podman", "exec", container, "curl", "--fail", "--silent",
                   "--cookie-jar", "/tmp/smoke-cookies", health[-1]).stdout
        form = LoginForm()
        form.feed(page)
        assert form.passwords, "Expected an unauthenticated login form"
        for key in form.fields:
            if "user" in key.lower():
                form.fields[key] = "gmail"
        for key in form.passwords:
            form.fields[key] = "invalid-fixture"
        result = run("podman", "exec", container, "curl", "--fail", "--silent",
                     "--cookie", "/tmp/smoke-cookies", "--cookie-jar", "/tmp/smoke-cookies",
                     "--dump-header", "/tmp/smoke-headers", "--data",
                     urllib.parse.urlencode(form.fields), health[-1])
        headers = run("podman", "exec", container, "cat", "/tmp/smoke-headers").stdout
        redirect = re.search(r"(?im)^location:\s*(.+)$", headers)
        if redirect:
            location = urllib.parse.urlsplit(redirect.group(1).strip())
            # Keep redirects inside the isolated namespace, including when the
            # application correctly generates an HTTPS URL for its real proxy.
            target = urllib.parse.urljoin(health[-1], location.path + "?" + location.query)
            result = run("podman", "exec", container, "curl", "--fail", "--silent",
                         "--cookie", "/tmp/smoke-cookies", target)
        rejected = LoginForm()
        rejected.feed(result.stdout)
        assert rejected.passwords, "Invalid credentials must leave the login form visible"
        run("podman", "exec", container, "nginx", "-t")
        fpm = run("podman", "exec", container, "php-fpm", "-tt")
        assert "listen = 127.0.0.1:9000" in fpm.stdout + fpm.stderr
        print("PASS: SQLite startup, HTTP health, login form, rejected authentication, nginx configuration, loopback PHP-FPM")
    finally:
        logs = run("podman", "logs", container, check=False)
        print(logs.stdout[-3000:])
        print(logs.stderr[-3000:])
        run("podman", "rm", "--force", container, check=False)
