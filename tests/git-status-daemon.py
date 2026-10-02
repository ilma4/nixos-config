"""Check the Git fields sent to Powerlevel10k's VCS renderer."""

import os
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

from git_status_support import daemon, request

FIELDS = (
    "branch", "remote_branch", "action", "staged", "unstaged", "untracked",
    "conflicted", "ahead", "behind", "stashes", "tag", "oid",
)


class GitStatusDaemonTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.repo = Path(self.tmp.name) / "repo"
        self.repo.mkdir()
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

    def status(self, git_env=None):
        payload = request(self.repo, git_env)
        result = subprocess.run(
            [str(daemon())],
            input=payload,
            check=True,
            capture_output=True,
        )
        if reference := os.environ.get("GIT_STATUS_REFERENCE"):
            old = subprocess.run(["zsh", "-f", reference],
                                 input=request(self.repo, git_env, quoted=True),
                                 check=True, capture_output=True)
            self.assertEqual(result.stdout, old.stdout)
            self.assertEqual(result.stderr, old.stderr)
        self.assertEqual(result.stderr, b"")
        self.assertTrue(result.stdout.startswith(b"1:"))
        self.assertTrue(result.stdout.endswith(b"\n"))
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

    def test_quoted_newlines_in_path_and_git_environment(self):
        renamed = self.repo.with_name("repo\nwith\\slashes")
        self.repo.rename(renamed)
        self.repo = renamed
        status = self.status({
            "GIT_CONFIG_COUNT": "1",
            "GIT_CONFIG_KEY_0": "user.name",
            "GIT_CONFIG_VALUE_0": "line one\nline two\\name",
        })
        self.assertEqual(status["branch"], "main")

    def test_tag(self):
        (self.repo / "staged").write_text("changed\n")
        self.git("commit", "-qam", "next")
        self.git("tag", "v1")
        self.assertEqual(self.status()["tag"], "v1")
        self.git("checkout", "-q", "--detach")
        self.assertEqual(self.status()["tag"], "v1")

    def test_multiple_tags_use_last_sorted_name(self):
        self.git("tag", "alpha")
        self.git("tag", "zeta")
        self.assertEqual(self.status()["tag"], "zeta")

    def test_unborn_branch(self):
        empty = self.repo / "empty"
        empty.mkdir()
        self.repo = empty
        self.git("init", "-q", "-b", "unborn")
        status = self.status()
        self.assertEqual((status["branch"], status["oid"]), ("unborn", "(initial)"))

    def test_reftable(self):
        self.git("refs", "migrate", "--ref-format=reftable")
        self.assertEqual(self.status()["branch"], "main")

    def test_actions_and_precedence_in_worktree(self):
        worktree = self.repo / "worktree"
        self.git("worktree", "add", "-qb", "worktree", str(worktree))
        self.repo = worktree
        git_dir = Path(self.git("rev-parse", "--absolute-git-dir").stdout.strip())
        for marker, action in (("BISECT_LOG", "bisect"), ("REVERT_HEAD", "revert"),
                               ("CHERRY_PICK_HEAD", "cherry-pick"), ("MERGE_HEAD", "merge"),
                               ("rebase-apply", "rebase"), ("rebase-merge", "rebase")):
            if marker.startswith("rebase-"):
                (git_dir / marker).mkdir()
            else:
                (git_dir / marker).write_text(self.git("rev-parse", "HEAD").stdout)
            self.assertEqual(self.status()["action"], action)

    def test_remote_name_with_slash_is_removed(self):
        self.git("remote", "add", "team/origin", str(self.repo))
        self.git("update-ref", "refs/remotes/team/origin/main", "HEAD")
        self.git("branch", "--set-upstream-to=team/origin/main")
        self.assertEqual(self.status()["remote_branch"], "main")

    def test_rename(self):
        self.git("mv", "staged", "renamed")
        self.assertEqual(self.status()["staged"], "1")

    def test_control_bytes_in_quoted_path_and_environment(self):
        # APFS requires UTF-8 paths; environment values can still contain any byte.
        name = bytes(i for i in range(1, 128) if i != ord("/"))
        renamed = self.repo.with_name(os.fsdecode(name))
        self.repo.rename(renamed)
        self.repo = renamed
        self.assertEqual(self.status({
            "GIT_CONFIG_COUNT": "1",
            "GIT_CONFIG_KEY_0": "user.name",
            "GIT_CONFIG_VALUE_0": os.fsdecode(bytes(range(1, 256))),
        })["branch"], "main")

    def test_environment_path_and_non_repo_across_requests(self):
        def payload(quoted=False):
            return (
                request(self.repo, {"GIT_DIR": str(self.repo / "absent")}, seq="1", quoted=quoted)
                + request(self.repo, seq="2", quoted=quoted)
                + request(self.repo, seq="3", path="/nonexistent", quoted=quoted)
                + request(self.repo.parent, seq="4", quoted=quoted)
                + request(self.repo, seq="5", quoted=quoted)
            )
        env = {**os.environ, "GIT_DIR": "/inherited/invalid"}
        result = subprocess.run([str(daemon())], input=payload(), env=env,
                                check=True, capture_output=True)
        if reference := os.environ.get("GIT_STATUS_REFERENCE"):
            old = subprocess.run(["zsh", "-f", reference], input=payload(True), env=env,
                                 check=True, capture_output=True)
            self.assertEqual(result.stdout, old.stdout)
        lines = result.stdout.splitlines()
        self.assertEqual(lines[0], b"1:")
        self.assertTrue(lines[1].startswith(b"2:main\x1f"))
        self.assertEqual(lines[2:4], [b"3:", b"4:"])
        self.assertTrue(lines[4].startswith(b"5:main\x1f"))
        self.assertEqual(result.stderr, b"")

    def test_truncated_requests_and_invalid_environment(self):
        payload = request(self.repo, {"GIT_DIR": "value"})
        for truncated in (payload[:1], payload[:2], payload[:-1], payload[:-5]):
            result = subprocess.run([str(daemon())], input=truncated,
                                    check=True, capture_output=True)
            self.assertEqual(result.stdout, b"")
        result = subprocess.run([str(daemon())], input=request(self.repo, {"OTHER": "value"}),
                                capture_output=True)
        self.assertEqual(result.returncode, 1)
        self.assertEqual(result.stdout, b"")

    def test_nul_in_environment_does_not_desynchronize_next_request(self):
        payload = (request(self.repo, {"GIT_TEST_VALUE": "before\0after"})
                   + request(self.repo, seq="2"))
        result = subprocess.run([str(daemon())], input=payload,
                                check=True, capture_output=True)
        self.assertTrue(result.stdout.startswith(b"1:\n2:main\x1f"))
        self.assertEqual(result.stderr, b"")

    def test_short_status_records_and_missing_header_values(self):
        fake_bin = self.repo.parent / "bin"
        fake_bin.mkdir()
        fake_git = fake_bin / "git"
        porcelain = ("# branch.head main\n# branch.oid abc\n# stash 7\n"
                     "# branch.head (detached)\n# branch.oid\n# stash\n"
                     "1\n1 \n1 M\n1 MM\n2 MM\nu\nu \n?\n? \n")
        fake_git.write_text(
            f"#!{sys.executable}\nimport sys\n"
            f"if sys.argv[3] == 'status': sys.stdout.write({porcelain!r})\n"
        )
        fake_git.chmod(0o755)
        result = subprocess.run([str(daemon())],
                                input=request(self.repo, path=str(fake_bin)),
                                check=True, capture_output=True)
        fields = result.stdout[2:-1].split(b"\x1f")
        self.assertEqual(fields[0], b"main")
        self.assertEqual(fields[3:7], [b"2", b"2", b"1", b"1"])
        self.assertEqual(fields[9], b"7")
        self.assertEqual(fields[11], b"abc")
        self.assertEqual(result.stderr, b"")

    def test_headers_are_replaced_and_cleared_between_requests(self):
        fake_bin = self.repo.parent / "headers-bin"
        fake_bin.mkdir()
        fake_git = fake_bin / "git"
        fake_git.write_text(
            f"#!{sys.executable}\nimport os, sys\n"
            "if sys.argv[3] == 'status':\n"
            "    sys.stdout.write(os.environ['GIT_TEST_STATUS'])\n"
            "    sys.exit(int(os.environ.get('GIT_TEST_EXIT', '0')))\n"
        )
        fake_git.chmod(0o755)
        headers = [
            "# branch.head " + "long" * 1000 + "\n# branch.oid abc\n",
            "# branch.head old\n# branch.head topic\n# branch.head (detached)\n"
            "# branch.oid old\n# branch.oid def\n"
            "# branch.upstream old/main\n# branch.upstream new/topic\n",
            "# branch.head failed\n# branch.oid failed\n",
            "# branch.head (detached)\n# branch.oid detached\n",
            "# branch.head unborn\n# branch.oid (initial)\n",
        ]
        payload = b"".join(request(self.repo, {
            "GIT_TEST_STATUS": status, "GIT_TEST_EXIT": str(int(i == 3)),
        }, seq=str(i), path=str(fake_bin)) for i, status in enumerate(headers, 1))
        result = subprocess.run([str(daemon())], input=payload,
                                check=True, capture_output=True)
        replies = result.stdout.splitlines()
        self.assertEqual(len(replies), 5)
        self.assertTrue(replies[0].startswith(b"1:" + b"long" * 1000 + b"\x1f"))
        self.assertTrue(replies[1].startswith(b"2:topic\x1fnew/topic\x1f"))
        self.assertTrue(replies[1].endswith(b"\x1fdef"))
        self.assertEqual(replies[2], b"3:")
        self.assertTrue(replies[3].startswith(b"4:\x1f\x1f\x1f"))
        self.assertTrue(replies[3].endswith(b"\x1fdetached"))
        self.assertTrue(replies[4].startswith(b"5:unborn\x1f\x1f"))
        self.assertTrue(replies[4].endswith(b"\x1f(initial)"))
        self.assertEqual(result.stderr, b"")

    def test_upstream_lookup_across_changing_raw_byte_headers(self):
        fake_bin = self.repo.parent / "upstream-bin"
        fake_bin.mkdir()
        fake_git = fake_bin / "git"
        fake_git.write_text(
            f"#!{sys.executable}\nimport os, sys\n"
            "branch = os.environ['GIT_TEST_BRANCH']\n"
            "if sys.argv[3] == 'status':\n"
            "    sys.stdout.buffer.write(os.fsencode('# branch.head ' + branch + '\\n'\n"
            "        '# branch.oid abc\\n# branch.upstream team/origin/topic\\n? '\n"
            "        + 'x' * int(os.environ['GIT_TEST_PATH_LENGTH'])))\n"
            "elif sys.argv[3] == 'config':\n"
            "    assert sys.argv[4:] == ['--get', 'branch.' + branch + '.remote']\n"
            "    print('team/origin')\n"
        )
        fake_git.chmod(0o755)
        branches = ["long" * 2000, "short", os.fsdecode(b"raw-\xff"), ""]
        payload = b"".join(request(self.repo, {
            "GIT_TEST_BRANCH": branch, "GIT_TEST_PATH_LENGTH": str(20000 // i),
        }, seq=str(i), path=str(fake_bin)) for i, branch in enumerate(branches, 1))
        result = subprocess.run([str(daemon())], input=payload,
                                check=True, capture_output=True)
        replies = result.stdout.splitlines()
        self.assertEqual(len(replies), len(branches))
        for i, (branch, reply) in enumerate(zip(branches, replies), 1):
            self.assertTrue(reply.startswith(str(i).encode() + b":"))
            fields = reply.split(b":", 1)[1].split(b"\x1f")
            self.assertEqual(len(fields), 12)
            self.assertEqual(fields[:2], [os.fsencode(branch), b"topic"])
            self.assertEqual(fields[5], b"1")
        self.assertEqual(result.stderr, b"")

    def test_optional_locks_nul_value_is_overridden_only_for_status(self):
        self.git("tag", "v1")
        payload = (request(self.repo, {"GIT_OPTIONAL_LOCKS": "before\0after"})
                   + request(self.repo, seq="2"))
        result = subprocess.run([str(daemon())], input=payload,
                                check=True, capture_output=True)
        first, second = result.stdout.splitlines()
        self.assertTrue(first.startswith(b"1:main\x1f"))
        self.assertEqual(first.split(b"\x1f")[-2], b"")
        self.assertEqual(second.split(b"\x1f")[-2], b"v1")
        self.assertEqual(result.stderr, b"")

    def test_git_commands_and_exact_environment(self):
        fake_bin = self.repo.parent / "bin"
        fake_bin.mkdir()
        log = self.repo.parent / "commands.jsonl"
        fake_git = fake_bin / "git"
        fake_git.write_text(
            f"#!{sys.executable}\n"
            "import json, os, sys\n"
            "with open(os.environ['TEST_GIT_LOG'], 'a') as log:\n"
            "    log.write(json.dumps({'args': sys.argv[1:], 'path': os.environ['PATH'],\n"
            "        'git_env': {k: v for k, v in os.environ.items() if k.startswith('GIT_')}}) + '\\n')\n"
            "command = sys.argv[3]\n"
            "if command == 'status':\n"
            "    print('# branch.oid abc\\n# branch.head main\\n# branch.upstream origin/main')\n"
            "elif command == 'config':\n"
            "    print('origin')\n"
            "elif command == 'tag':\n"
            "    print('alpha\\nzeta')\n"
            "elif command == 'rev-parse':\n"
            "    print(sys.argv[2] + '/.git')\n"
        )
        fake_git.chmod(0o755)
        forwarded = {"GIT_OPTIONAL_LOCKS": "1",
                     "GIT_TEST_VALUE": os.fsdecode(bytes(range(1, 256))) + "é😀"}
        env = {**os.environ, "TEST_GIT_LOG": str(log), "GIT_DIR": "/bad/inherited"}
        commands = [[str(daemon())]]
        if reference := os.environ.get("GIT_STATUS_REFERENCE"):
            commands.append(["zsh", "-f", reference])
        for locale in ("C", "en_US.UTF-8" if sys.platform == "darwin" else "C.UTF-8"):
            for overrides in ({}, {"GIT_TEST_VALUE": forwarded["GIT_TEST_VALUE"]}, forwarded):
                replies = []
                for command in commands:
                    payload = request(self.repo, overrides, path=str(fake_bin),
                                      quote_env={**os.environ, "LC_ALL": locale},
                                      quoted=command[0] == "zsh")
                    log.unlink(missing_ok=True)
                    result = subprocess.run(command, input=payload, env=env,
                                            check=True, capture_output=True)
                    self.assertEqual(result.stderr, b"")
                    replies.append(result.stdout)
                    calls = [json.loads(line) for line in log.read_text().splitlines()]
                    self.assertEqual([call["args"] for call in calls], [
                        ["-C", str(self.repo), "status", "--porcelain=v2", "--branch", "--show-stash"],
                        ["-C", str(self.repo), "config", "--get", "branch.main.remote"],
                        ["-C", str(self.repo), "tag", "--points-at", "HEAD", "--sort=refname"],
                        ["-C", str(self.repo), "rev-parse", "--absolute-git-dir"],
                    ])
                    for i, call in enumerate(calls):
                        self.assertEqual(call["path"], str(fake_bin))
                        expected = dict(overrides)
                        if i == 0:
                            expected["GIT_OPTIONAL_LOCKS"] = "0"
                        self.assertEqual(call["git_env"], expected)
                self.assertTrue(all(reply == replies[0] for reply in replies))

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
