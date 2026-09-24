"""Check the Git fields sent to Powerlevel10k's VCS renderer."""

import os
from pathlib import Path
import subprocess
import tempfile
import unittest


DAEMON = Path(__file__).resolve().parents[1] / "home/git-status-daemon.zsh"
FIELDS = (
    "branch", "remote_branch", "action", "staged", "unstaged", "untracked",
    "conflicted", "ahead", "behind", "stashes", "tag", "oid",
)


class GitStatusDaemonTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.repo = Path(self.tmp.name)
        self.git("init", "-q", "-b", "main")
        self.git("config", "user.name", "Prompt Test")
        self.git("config", "user.email", "prompt@example.invalid")
        (self.repo / "staged").write_text("original\n")
        (self.repo / "unstaged").write_text("original\n")
        self.git("add", ".")
        self.git("commit", "-qm", "initial")

    def git(self, *args, check=True):
        return subprocess.run(
            ["git", "-C", str(self.repo), *args],
            check=check,
            capture_output=True,
            text=True,
        )

    def status(self):
        request = (f"1\0{self.repo}\0{os.environ['PATH']}\0" + "0\0").encode()
        result = subprocess.run(
            ["zsh", "-f", str(DAEMON)],
            input=request,
            check=True,
            capture_output=True,
        )
        self.assertEqual(result.stderr, b"")
        self.assertTrue(result.stdout.startswith(b"1:"))
        self.assertTrue(result.stdout.endswith(b"\0"))
        fields = result.stdout[2:-1].decode().split("\x1f")
        self.assertEqual(len(fields), len(FIELDS))
        return dict(zip(FIELDS, fields))

    def test_staged_unstaged_and_untracked_directory(self):
        (self.repo / "staged").write_text("changed\n")
        self.git("add", "staged")
        (self.repo / "unstaged").write_text("changed\n")
        (self.repo / "new").mkdir()
        (self.repo / "new" / "one").write_text("new\n")
        (self.repo / "new" / "two").write_text("new\n")
        status = self.status()
        self.assertEqual(status["branch"], "main")
        self.assertEqual((status["staged"], status["unstaged"], status["untracked"]),
                         ("1", "1", "1"))

    def test_conflict(self):
        (self.repo / "staged").write_text("base\n")
        self.git("add", "staged")
        self.git("commit", "-qm", "base")
        self.git("checkout", "-qb", "other")
        (self.repo / "staged").write_text("other\n")
        self.git("commit", "-qam", "other")
        self.git("checkout", "-q", "main")
        (self.repo / "staged").write_text("main\n")
        self.git("commit", "-qam", "main")
        self.assertNotEqual(self.git("merge", "other", check=False).returncode, 0)
        status = self.status()
        self.assertEqual((status["action"], status["conflicted"]), ("merge", "1"))

    def test_detached_commit_and_stash(self):
        (self.repo / "staged").write_text("changed\n")
        self.git("stash", "push", "-q")
        self.assertEqual(self.status()["stashes"], "1")
        self.git("checkout", "-q", "--detach")
        oid = self.git("rev-parse", "HEAD").stdout.strip()
        status = self.status()
        self.assertEqual((status["branch"], status["oid"], status["stashes"]),
                         ("", oid, "1"))

    def test_branch_name_is_preserved_for_renderer(self):
        branch = "feature%" + "long" * 8
        self.git("checkout", "-qb", branch)
        self.assertEqual(self.status()["branch"], branch)

    def test_tag(self):
        (self.repo / "staged").write_text("changed\n")
        self.git("commit", "-qam", "next")
        self.git("tag", "v1")
        self.assertEqual(self.status()["tag"], "v1")
        self.git("checkout", "-q", "--detach")
        self.assertEqual(self.status()["tag"], "v1")

    def test_ahead_behind_and_upstream(self):
        self.git("branch", "upstream")
        self.git("branch", "--set-upstream-to=upstream", "main")
        (self.repo / "main-only").write_text("main\n")
        self.git("add", "main-only")
        self.git("commit", "-qm", "main")
        self.git("checkout", "-q", "upstream")
        (self.repo / "upstream-only").write_text("upstream\n")
        self.git("add", "upstream-only")
        self.git("commit", "-qm", "upstream")
        self.git("checkout", "-q", "main")
        status = self.status()
        self.assertEqual((status["remote_branch"], status["ahead"], status["behind"]),
                         ("upstream", "1", "1"))


if __name__ == "__main__":
    unittest.main()
