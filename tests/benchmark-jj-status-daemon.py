"""Measure JJ refreshes, including snapshotting, in isolated repositories.

Run with GIT_STATUS_DAEMON=/path/to/worker python3 tests/benchmark-jj-status-daemon.py.
"""
import argparse
import json
import os
from pathlib import Path
import platform
import statistics
import subprocess
import tempfile
import time
from git_status_support import daemon, request


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--samples', type=int, default=100)
    parser.add_argument('--tracked-remote', action='store_true')
    parser.add_argument('--depth', type=int, default=1,
                        help='commits between the bookmark and working copy (default: 1)')
    args = parser.parse_args()
    if args.depth < 1:
        parser.error('--depth must be at least 1')
    report = {'platform': platform.platform(), 'jj': subprocess.check_output(['jj','--version'], text=True).strip(), 'samples': args.samples, 'tracked_remote': args.tracked_remote, 'cases': {}}
    report['depth'] = args.depth
    with tempfile.TemporaryDirectory(prefix='jj-status-benchmark-') as tmp:
        root = Path(tmp)
        config = root / 'config.toml'
        config.write_text('[user]\nname="Benchmark"\nemail="benchmark@example.invalid"\n[signing]\nbehavior="drop"\n')
        env = {**os.environ, 'JJ_CONFIG': str(config)}
        for size in (10, 5000):
            repo = root / str(size)
            subprocess.run(['jj','git','init','--colocate',str(repo)],env=env,check=True,capture_output=True)
            for n in range(size): (repo / f'file-{n}').write_text('initial\n')
            subprocess.run(['jj','-R',str(repo),'bookmark','create','main'],env=env,check=True,capture_output=True)
            if args.tracked_remote:
                target = subprocess.check_output(['jj','-R',str(repo),'log','-G','-r','main','-T','commit_id'], env=env, text=True)
                subprocess.run(['git','-C',str(repo),'update-ref','refs/remotes/origin/main',target], check=True)
                subprocess.run(['jj','-R',str(repo),'git','import'],env=env,check=True,capture_output=True)
                subprocess.run(['jj','-R',str(repo),'bookmark','track','main@origin'],env=env,check=True,capture_output=True)
            for _ in range(args.depth):
                subprocess.run(['jj','-R',str(repo),'new'],env=env,check=True,capture_output=True)
            with subprocess.Popen([str(daemon())],stdin=subprocess.PIPE,stdout=subprocess.PIPE) as worker:
                payload=request(repo, {'JJ_CONFIG': str(config)})
                def refresh():
                    start=time.perf_counter_ns()
                    worker.stdin.write(payload); worker.stdin.flush()
                    reply=worker.stdout.readline()
                    assert reply.startswith(b'1:jj\x1f'), reply
                    return (time.perf_counter_ns()-start)/1e6
                for dirty in (False,True):
                    if dirty:
                        for n in range(size): (repo / f'file-{n}').write_text('changed\n')
                    first=refresh()
                    for _ in range(10): refresh()
                    samples=[refresh() for _ in range(args.samples)]
                    report['cases'][f'{size}_files_{"dirty" if dirty else "clean"}']={'first_ms':first,'median_ms':statistics.median(samples),'p95_ms':sorted(samples)[int(0.95 * (len(samples) - 1))],'samples_ms':samples}
                worker.stdin.close()
    print(json.dumps(report,indent=2))


if __name__ == '__main__':
    main()
