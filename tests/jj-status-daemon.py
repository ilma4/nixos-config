"""JJ backend integration tests against real temporary repositories."""
import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest
from git_status_support import daemon, request


class JJStatusTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)
        self.repo = self.root / 'repo'
        self.env = {**os.environ, 'JJ_CONFIG': str(self.root / 'config.toml')}
        (self.root / 'config.toml').write_text('[user]\nname="Prompt"\nemail="prompt@example.invalid"\n[signing]\nbehavior="drop"\n')
        self.jj('git', 'init', '--colocate', str(self.repo), cwd=self.root)

    def jj(self, *args, cwd=None):
        return subprocess.run(['jj', '--color=never', *args], cwd=cwd or self.repo,
                              env=self.env, capture_output=True, check=True).stdout.decode().strip()

    def status(self, directory=None):
        reply = subprocess.run([str(daemon())], input=request(directory or self.repo, {'JJ_CONFIG': self.env['JJ_CONFIG']}),
                               env=self.env, capture_output=True, check=True)
        self.assertEqual(reply.stderr, b'')
        fields = reply.stdout.removeprefix(b'1:').rstrip(b'\n').decode().split('\x1f')
        self.assertEqual(fields[0], 'jj', reply.stdout)
        self.assertEqual(len(fields), 9)
        return fields

    def test_fallback_and_current_edits(self):
        self.assertEqual(self.status()[1], self.jj('log', '--no-graph', '-r', '@', '-T', 'change_id.short(8)'))
        (self.repo / 'tracked').write_text('base\n')
        (self.repo / 'removed').write_text('base\n')
        self.jj('new')
        self.assertEqual(self.status()[3:7], ['0','0','0','0'])
        (self.repo / 'tracked').write_text('modified\n')
        (self.repo / 'removed').unlink()
        (self.repo / 'added').write_text('new\n')
        self.assertEqual(self.status()[3:7], ['1','1','1','0'])

    def test_bookmark_distance_ties_and_subdirectory(self):
        self.jj('bookmark', 'create', 'old')
        self.jj('new')
        self.jj('bookmark', 'create', 'zeta')
        self.jj('bookmark', 'create', 'alpha')
        self.jj('new')
        self.jj('new')
        child = self.repo / 'child'
        child.mkdir()
        self.assertEqual(self.status(child)[1], 'alpha')
        self.jj('bookmark', 'create', 'current')
        self.assertEqual(self.status()[1], 'current')

    def test_merge_shortest_path_and_conflict(self):
        (self.repo / 'file').write_text('base\n')
        self.jj('bookmark', 'create', 'base')
        self.jj('new')
        (self.repo / 'file').write_text('left\n')
        self.jj('bookmark', 'create', 'left')
        self.jj('new', 'base')
        (self.repo / 'file').write_text('right\n')
        self.jj('bookmark', 'create', 'right')
        self.jj('new')
        self.jj('new')
        self.jj('new', 'left', '@')
        state = self.status()
        self.assertEqual(state[1], 'left')
        self.assertEqual(state[6], '1')

    def test_upstream_divergence_includes_working_copy(self):
        # Keep @ editable when the test introduces a remote bookmark on it.
        with (self.root / 'config.toml').open('a') as config:
            config.write('[revset-aliases]\n"immutable_heads()"="none()"\n')
        # Export a local bookmark then import a remote-tracking ref in the same repository.
        (self.repo / 'base').write_text('base\n')
        self.jj('bookmark', 'create', 'main')
        self.jj('git', 'export')
        subprocess.run(['git', '-C', str(self.repo), 'update-ref', 'refs/remotes/origin/main',
                        self.jj('log', '-G', '-r', '@', '-T', 'commit_id')], check=True)
        self.jj('git', 'import')
        self.jj('bookmark', 'track', 'main@origin')
        self.assertEqual(self.status()[7:], ['0', '0'])
        self.jj('new')
        self.jj('new')
        self.assertEqual(self.status()[7:], ['2', '0'])
        self.jj('new', 'main')
        (self.repo / 'remote').write_text('remote\n')
        remote = self.jj('log', '-G', '-r', '@', '-T', 'commit_id')
        self.jj('new', 'main')
        subprocess.run(['git', '-C', str(self.repo), 'update-ref', 'refs/remotes/origin/main', remote], check=True)
        self.jj('git', 'import')
        self.jj('bookmark', 'set', 'main', '-r', '@', '--allow-backwards')
        self.assertEqual(self.status()[7:], ['1', '1'])
        self.jj('edit', 'main@origin-')
        self.jj('bookmark', 'set', 'main', '-r', '@', '--allow-backwards')
        self.assertEqual(self.status()[7:], ['0', '1'])
        self.jj('bookmark', 'untrack', 'main@origin')
        self.assertEqual(self.status()[7:], ['0', '0'])

    def test_multiple_remote_targets_and_origin_preference(self):
        self.jj('bookmark', 'create', 'main')
        base = self.jj('log', '-G', '-r', '@', '-T', 'commit_id')
        self.jj('new')
        tip = self.jj('log', '-G', '-r', '@', '-T', 'commit_id')
        self.jj('new')

        def track(remote, target):
            subprocess.run(['git', '-C', str(self.repo), 'update-ref',
                            f'refs/remotes/{remote}/main', target], check=True)
            self.jj('git', 'import')
            self.jj('bookmark', 'track', f'main@{remote}')

        track('first', base)
        track('second', base)
        self.assertEqual(self.status()[7:], ['2', '0'])
        track('second', tip)
        self.assertEqual(self.status()[7:], ['0', '0'])
        track('origin', base)
        self.assertEqual(self.status()[7:], ['2', '0'])

    def test_escaped_bookmark_with_upstream(self):
        with (self.root / 'config.toml').open('a') as config:
            config.write('[revset-aliases]\n"immutable_heads()"="none()"\n')
        name = 'topic"quoted|%'
        self.jj('bookmark', 'create', json.dumps(name))
        base = self.jj('log', '-G', '-r', '@', '-T', 'commit_id')
        subprocess.run(['git', '-C', str(self.repo), 'update-ref',
                        f'refs/remotes/origin/{name}', base], check=True)
        self.jj('git', 'import')
        self.jj('bookmark', 'track', f'{json.dumps(name)}@origin')
        self.jj('new')
        state = self.status()
        self.assertEqual(state[1], 'topic\\"quoted|%')
        self.assertEqual(state[7:], ['1', '0'])

    def test_missing_jj_recovers_in_same_worker(self):
        payload = request(self.repo, path='/missing') + request(self.repo, {'JJ_CONFIG': self.env['JJ_CONFIG']}, seq='2')
        reply = subprocess.run([str(daemon())], input=payload, env=self.env, capture_output=True, check=True)
        self.assertTrue(reply.stdout.startswith(b'1:\n2:jj\x1f'), reply.stdout)

    def test_depth_expansion(self):
        self.jj('bookmark', 'create', 'distant')
        for _ in range(18):
            self.jj('new')
        self.assertEqual(self.status()[1], 'distant')

    def test_nested_git_boundary_and_explicit_override(self):
        nested = self.repo / 'nested'
        nested.mkdir()
        subprocess.run(['git', 'init', '-q', '-b', 'nested', str(nested)], check=True)
        reply = subprocess.run([str(daemon())], input=request(nested), env=self.env,
                               capture_output=True, check=True).stdout
        self.assertTrue(reply.startswith(b'1:nested\x1f'), reply)
        reply = subprocess.run([str(daemon())], input=request(self.repo, {'GIT_DIR': str(nested / '.git')}),
                               env=self.env, capture_output=True, check=True).stdout
        self.assertTrue(reply.startswith(b'1:nested\x1f'), reply)


if __name__ == '__main__':
    unittest.main()
