"""Exercise the interactive Git prompt and its single daemon lifecycle."""

import os
from pathlib import Path
import pty
import re
import select
import shlex
import signal
import subprocess
import tempfile
import time
import unittest


ROOT = Path(__file__).resolve().parents[1]
CLIENT = ROOT / "home/git-status-client.zsh"
DAEMON = ROOT / "home/git-status-daemon.zsh"


class GitStatusClientTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)
        self.repo = self.root / "repo"
        self.repo.mkdir()
        (self.repo / "child").mkdir()
        subprocess.run(["git", "-C", str(self.repo), "init", "-q", "-b", "main"], check=True)
        subprocess.run(["git", "-C", str(self.repo), "config", "user.name", "Prompt Test"], check=True)
        subprocess.run(["git", "-C", str(self.repo), "config", "user.email", "prompt@example.invalid"], check=True)
        (self.repo / "tracked").write_text("initial\n")
        subprocess.run(["git", "-C", str(self.repo), "add", "tracked"], check=True)
        subprocess.run(["git", "-C", str(self.repo), "commit", "-qm", "initial"], check=True)

    def start_shell(self, separate_job=False):
        zdot = self.root / "zdot"
        zdot.mkdir()
        client = CLIENT
        if separate_job:
            # A separate process group exposes accidental terminal access.
            client = self.root / "git-status-client-monitor.zsh"
            client.write_text(CLIENT.read_text().replace(
                "setopt local_options no_monitor", "setopt local_options monitor"
            ))
        zdot.joinpath(".zshrc").write_text(
            f"source {shlex.quote(str(client))} zsh {shlex.quote(str(DAEMON))}\n"
            "setopt prompt_subst\n"
            "PROMPT='I4_STATUS:${PWD:t}:${_I4_GIT_STATUS_READY}:"
            "${_I4_GIT_STATUS_FAILED}:${VCS_STATUS_LOCAL_BRANCH}> '\n"
        )
        master, slave = pty.openpty()
        process = subprocess.Popen(
            ["zsh", "-i"], cwd=self.repo,
            env={**os.environ, "ZDOTDIR": str(zdot)},
            stdin=slave, stdout=slave, stderr=slave, start_new_session=True,
        )
        os.close(slave)

        def cleanup():
            try:
                os.killpg(process.pid, signal.SIGKILL)
            except ProcessLookupError:
                pass
            process.wait()
            os.close(master)

        self.addCleanup(cleanup)
        return master

    def read_until(self, master, *markers, timeout=5):
        output = b""
        deadline = time.monotonic() + timeout
        while not all(marker in output for marker in markers):
            remaining = deadline - time.monotonic()
            if remaining <= 0:
                self.fail(f"prompt never showed {markers!r}; output: {output!r}")
            if select.select([master], [], [], remaining)[0]:
                output += os.read(master, 65536)
        return output

    def worker_pid(self, master, dirname):
        os.write(master, b"print -r -- worker:$_I4_GIT_STATUS_PID\n")
        output = self.read_until(
            master, b"I4_STATUS:" + dirname + b":1:0:main", b"worker:"
        )
        return int(re.search(rb"worker:(\d+)\r", output).group(1))

    def test_worker_keeps_running_across_cd_and_foreground_command(self):
        master = self.start_shell(separate_job=True)
        self.read_until(master, b"I4_STATUS:repo:1:0:main")
        worker = self.worker_pid(master, b"repo")
        self.addCleanup(lambda: subprocess.run(
            ["kill", "-KILL", str(worker)], capture_output=True
        ))
        for command, dirname in ((b"cd child\n", b"child"),
                                 (b"sleep 0.2\n", b"child"),
                                 (b"cd ..\n", b"repo")):
            os.write(master, command)
            self.read_until(master, b"I4_STATUS:" + dirname + b":1:0:main")
            state = subprocess.run(
                ["ps", "-o", "stat=", "-p", str(worker)],
                check=True, capture_output=True, text=True,
            ).stdout.strip()
            self.assertNotIn("T", state, state)
        self.assertEqual(self.worker_pid(master, b"repo"), worker)

    def test_worker_exit_is_reported_once_without_restart(self):
        master = self.start_shell()
        self.read_until(master, b"I4_STATUS:repo:1:0:main")
        worker = self.worker_pid(master, b"repo")
        os.write(master, b"_i4_git_status_start\n")
        output = self.read_until(
            master, b"refusing a second launch", b"I4_STATUS:repo:1:0:main"
        )
        self.assertIn(b"already launched", output)
        self.assertEqual(self.worker_pid(master, b"repo"), worker)
        os.kill(worker, signal.SIGTERM)
        output = self.read_until(
            master, b"failed: response pipe closed", b"I4_STATUS:repo:0:1:main"
        )
        self.assertIn(f"PID {worker}".encode(), output)
        os.write(master, b"cd child\n")
        output = self.read_until(master, b"I4_STATUS:child:0:1:main")
        self.assertNotIn(b"git status daemon (PID", output)
        os.write(master, b"print -r -- worker:$_I4_GIT_STATUS_PID\n")
        output = self.read_until(master, b"worker:0\r", b"I4_STATUS:child:0:1:main")
        self.assertNotIn(b"git status daemon (PID", output)


if __name__ == "__main__":
    unittest.main()
