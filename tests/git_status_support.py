"""Build the native worker once, or test the supplied Nix-built binary."""

import atexit
from functools import lru_cache
import os
from pathlib import Path
import subprocess
import tempfile


@lru_cache(maxsize=1)
def daemon():
    if path := os.environ.get("GIT_STATUS_DAEMON"):
        return Path(path).resolve()
    tmp = tempfile.TemporaryDirectory(prefix="git-status-daemon-")
    atexit.register(tmp.cleanup)
    binary = Path(tmp.name) / "git-status-daemon"
    source = Path(__file__).resolve().parents[1] / "home/git-status-daemon.rs"
    subprocess.run([
        "rustc", "--edition=2021", "-C", "opt-level=3", "-C", "strip=symbols",
        str(source), "-o", str(binary),
    ], check=True)
    return binary


def request(directory, git_env=None, seq="1", path=None, quote_env=None, quoted=False):
    git_env = git_env or {}
    values = [seq, str(directory), path or os.environ["PATH"], str(len(git_env))]
    for name, value in git_env.items():
        values.extend([name, value])
    if not quoted:
        fields = [os.fsencode(value) for value in values]
        return b"".join(str(len(field)).encode() + b"\n" + field for field in fields)
    return subprocess.run(
        ["zsh", "-fc", 'for value in "$@"; do print -r -- "${(q)value}"; done',
         "zsh", *values], check=True, capture_output=True, env=quote_env,
    ).stdout
