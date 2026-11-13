"""Exercise the interactive Git prompt and its single daemon lifecycle."""

import io
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

from git_status_support import daemon

ROOT = Path(__file__).resolve().parents[1]
CLIENT = Path(os.environ.get("GIT_STATUS_CLIENT", ROOT / "home/git-status-client.zsh"))


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

    def start_shell(self, separate_job=False, theme=None):
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
            f"source {shlex.quote(str(client))} {shlex.quote(str(daemon()))}\n"
            "setopt prompt_subst\n"
            "PROMPT='I4_STATUS:${PWD:t}:${_I4_GIT_STATUS_READY}:"
            "${_I4_GIT_STATUS_FAILED}:${VCS_STATUS_LOCAL_BRANCH}:${_I4_STATUS_BACKEND}:${_I4_JJ_LABEL}:${_I4_JJ_ADDED}:${_I4_JJ_MODIFIED}:${_I4_JJ_DELETED}> '\n"
        )
        if theme:
            with zdot.joinpath(".zshrc").open('a') as rc:
                rc.write(f"source {shlex.quote(theme)}\nsource {shlex.quote(str(ROOT / 'dotfiles/p10k.zsh'))}\n")
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
            # Require a fresh reply, including when the directory is unchanged.
            os.write(master, b"_I4_GIT_STATUS_OUTPUT= _I4_GIT_STATUS_READY=0; " + command)
            self.read_until(master, b"I4_STATUS:" + dirname + b":1:0:main")
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

    @unittest.skipUnless(os.environ.get('I4_TEST_P10K_THEME'), 'Set I4_TEST_P10K_THEME for actual theme rendering')
    def test_actual_jj_theme_rendering(self):
        subprocess.run(['jj', 'git', 'init', '--colocate', str(self.repo)], check=True, capture_output=True)
        subprocess.run(['jj', '-R', str(self.repo), 'bookmark', 'create', 'prompt-test'], check=True, capture_output=True)
        (self.repo / 'new-file').write_text('new\n')
        master = self.start_shell(theme=os.environ['I4_TEST_P10K_THEME'])
        self.read_until(master, b'jj:prompt-test', b'+1')

    def test_jj_divergence_rendering(self):
        result = subprocess.run(['zsh', '-fc', r'''
            source "$1"
            function p10k() { print -r -- "$@" }
            _I4_GIT_STATUS_READY=1 _I4_STATUS_BACKEND=jj _I4_JJ_LABEL=main
            _I4_JJ_AHEAD=3 _I4_JJ_BEHIND=2
            prompt_git_status
            _I4_JJ_AHEAD=0 _I4_JJ_BEHIND=0
            prompt_git_status
        ''', 'zsh', str(ROOT / 'dotfiles/p10k.zsh')], check=True, capture_output=True)
        first, second = result.stdout.decode().splitlines()
        self.assertIn('⇡3', first)
        self.assertIn('⇣2', first)
        self.assertNotIn('⇡', second)
        self.assertNotIn('⇣', second)

    def test_jj_refresh_and_git_transition(self):
        subprocess.run(['jj', 'git', 'init', '--colocate', str(self.repo)], check=True,
                       capture_output=True)
        subprocess.run(['jj', '-R', str(self.repo), 'bookmark', 'create', 'prompt-test'],
                       check=True, capture_output=True)
        master = self.start_shell()
        self.read_until(master, b':jj:prompt-test:0:0:0>')
        (self.repo / 'new-file').write_text('new\n')
        os.write(master, b'\n')
        self.read_until(master, b':jj:prompt-test:1:0:0>')
        nested = self.repo / 'git-only'
        nested.mkdir()
        subprocess.run(['git', 'init', '-q', '-b', 'nested', str(nested)], check=True)
        os.write(master, b'cd git-only\n')
        self.read_until(master, b'I4_STATUS:git-only:1:0:nested:git:')
        os.write(master, b'cd ..\n')
        self.read_until(master, b':jj:prompt-test:')

    def test_request_preserves_bytes_and_multibyte_option(self):
        value = bytes(range(1, 256)) + "é😀".encode()
        result = subprocess.run([
            "zsh", "-fc", r'''
                setopt typeset_silent multibyte
                PATH=
                source "$1" /unused
                PWD=$'/a path/é😀/new\nline'
                export GIT_TEST_BYTES=$2 GIT_TEST_EMPTY= GIT_TEST_NUL=$'before\0after'
                typeset GIT_TEST_UNEXPORTED=ignored
                exec {_I4_GIT_STATUS_REQUEST_FD}>&1
                _I4_GIT_STATUS_SEQ=1234
                _i4_git_status_send
                [[ -o multibyte ]] || exit 1
                unsetopt multibyte
                _i4_git_status_send
                [[ ! -o multibyte ]] || exit 2
            ''', "zsh", str(CLIENT), os.fsdecode(value),
        ], check=True, capture_output=True,
            env={k: v for k, v in os.environ.items() if not k.startswith("GIT_")})
        self.assertEqual(result.stderr, b"")
        stream = io.BytesIO(result.stdout)

        def field():
            return stream.read(int(stream.readline()))

        for _ in range(2):
            self.assertEqual(field(), b"1234")
            self.assertEqual(field(), "/a path/é😀/new\nline".encode())
            self.assertEqual(field(), b"")
            count = int(field())
            self.assertEqual({field(): field() for _ in range(count)}, {
                b"GIT_TEST_BYTES": value, b"GIT_TEST_EMPTY": b"",
                b"GIT_TEST_NUL": b"before\0after",
            })
        self.assertEqual(stream.read(), b"")

    def test_large_request_is_written_completely(self):
        result = subprocess.run([
            "zsh", "-fc", r'''
                PATH=
                source "$1" /unused
                export GIT_TEST_LARGE=${(l:300000::x:)empty}
                exec {_I4_GIT_STATUS_REQUEST_FD}>&1
                _i4_git_status_send
            ''', "zsh", str(CLIENT),
        ], check=True, capture_output=True,
            env={k: v for k, v in os.environ.items() if not k.startswith("GIT_")})
        self.assertEqual(result.stderr, b"")
        stream = io.BytesIO(result.stdout)

        def field():
            return stream.read(int(stream.readline()))

        for _ in range(3):
            field()  # sequence, directory, PATH
        self.assertEqual(field(), b"1")
        self.assertEqual((field(), field()), (b"GIT_TEST_LARGE", b"x" * 300000))
        self.assertEqual(stream.read(), b"")


if __name__ == "__main__":
    unittest.main()
