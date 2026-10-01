"""Compare worker RSS and request latency against a saved Zsh or Rust worker.

Usage: python3 tests/benchmark-git-status-daemon.py --legacy /tmp/legacy.zsh
       [--native /nix/store/.../git-status-daemon] [--samples 100]
       Use --baseline /tmp/before instead of --legacy for a quoted-line Rust baseline.
Reports JSON including raw samples. Git subprocesses are excluded from RSS.
"""

import argparse
import json
import os
from pathlib import Path
import platform
import random
import statistics
import subprocess
import sys
import tempfile
import time

from git_status_support import daemon, request


def git(repo, *args):
    return subprocess.run(["git", "-C", str(repo), *args], check=True,
                          capture_output=True).stdout


def init(repo, files):
    repo.mkdir()
    git(repo, "init", "-q", "-b", "main")
    git(repo, "config", "user.name", "Benchmark")
    git(repo, "config", "user.email", "benchmark@example.invalid")
    git(repo, "config", "core.fsmonitor", "false")
    git(repo, "config", "core.untrackedCache", "false")
    for n in range(files):
        (repo / f"file-{n:05}").write_text("initial\n")
    git(repo, "add", ".")
    git(repo, "commit", "-qm", "initial")


def rss(pid):
    # ps reports resident memory in KiB on both macOS and Linux.
    return int(subprocess.check_output(["ps", "-o", "rss=", "-p", str(pid)]))


def roundtrip(worker, payload):
    start = time.perf_counter_ns()
    worker.stdin.write(payload)
    worker.stdin.flush()
    response = worker.stdout.readline()
    elapsed = (time.perf_counter_ns() - start) / 1_000_000
    if not response.startswith(b"1:") or not response.endswith(b"\n"):
        raise RuntimeError(f"worker exited or returned invalid response: {response!r}")
    return elapsed, response


def summarize(samples):
    ordered = sorted(samples)
    return {"median": statistics.median(samples),
            "p95": ordered[int(0.95 * (len(ordered) - 1))],
            "min": min(samples), "max": max(samples), "samples": samples}


def measure(commands, repo, samples, startup_samples):
    payloads = {name: request(repo, quoted=name not in ("rust", "after"))
                for name in commands}
    workers = {name: subprocess.Popen(command, stdin=subprocess.PIPE,
                                     stdout=subprocess.PIPE, stderr=subprocess.DEVNULL)
               for name, command in commands.items()}
    timings = {name: [] for name in commands}
    memory = {name: [] for name in commands}
    rng = random.Random(0)
    try:
        for _ in range(10):
            replies = [roundtrip(worker, payloads[name])[1]
                       for name, worker in workers.items()]
            assert replies[0] == replies[1], (repo, replies)
        for i in range(samples):
            order = list(workers)
            rng.shuffle(order)
            replies = []
            for name in order:
                elapsed, reply = roundtrip(workers[name], payloads[name])
                timings[name].append(elapsed)
                replies.append(reply)
            assert replies[0] == replies[1], (repo, replies)
            if i % 10 == 0:
                for name, worker in workers.items():
                    memory[name].append(rss(worker.pid))
    finally:
        for worker in workers.values():
            worker.stdin.close()
            worker.wait(timeout=10)
            worker.stdout.close()
    startup = {name: [] for name in commands}
    for _ in range(startup_samples):
        order = list(commands)
        rng.shuffle(order)
        for name in order:
            start = time.perf_counter_ns()
            with subprocess.Popen(commands[name], stdin=subprocess.PIPE,
                                  stdout=subprocess.PIPE, stderr=subprocess.DEVNULL) as worker:
                roundtrip(worker, payloads[name])
                startup[name].append((time.perf_counter_ns() - start) / 1_000_000)
                worker.stdin.close()
    return {name: {"roundtrip_ms": summarize(timings[name]),
                   "worker_rss_kib": summarize(memory[name]),
                   "start_to_first_response_ms": summarize(startup[name])}
            for name in commands}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    baseline = parser.add_mutually_exclusive_group(required=True)
    baseline.add_argument("--legacy", type=Path, help="Original quoted-line Zsh worker.")
    baseline.add_argument("--baseline", type=Path, help="Previous quoted-line Rust worker.")
    parser.add_argument("--native", type=Path)
    parser.add_argument("--samples", default=100, type=int)
    parser.add_argument("--startup-samples", default=30, type=int)
    parser.add_argument("--case", action="append", choices=(
        "non_repo", "small_clean_10_files", "checkout", "large_clean_5000_files",
        "large_dirty_5000_modified_200_untracked"),
        help="Measure only selected cases (repeat to select several).")
    args = parser.parse_args()
    native = str(args.native.resolve() if args.native else daemon())
    commands = ({"before": [str(args.baseline.resolve())], "after": [native]}
                if args.baseline else
                {"zsh": ["zsh", "-f", str(args.legacy.resolve())], "rust": [native]})
    root = Path(__file__).resolve().parents[1]
    report = {"platform": platform.platform(), "machine": platform.machine(),
              "git": subprocess.check_output(["git", "--version"], text=True).strip(),
              "commands": commands, "samples": args.samples,
              "startup_samples": args.startup_samples, "warmups": 10,
              "cases": {}}
    with tempfile.TemporaryDirectory(prefix="git-status-benchmark-") as tmp:
        tmp = Path(tmp)
        small, large = tmp / "small", tmp / "large"
        init(small, 10)
        init(large, 5000)
        cases = {"non_repo": tmp, "small_clean_10_files": small,
                 "checkout": root, "large_clean_5000_files": large}
        for name, repo in cases.items():
            if args.case and name not in args.case:
                continue
            report["cases"][name] = measure(commands, repo, args.samples, args.startup_samples)
            print(f"Measured {name}", file=sys.stderr, flush=True)
        dirty_case = "large_dirty_5000_modified_200_untracked"
        if not args.case or dirty_case in args.case:
            for n in range(5000):
                (large / f"file-{n:05}").write_text("changed\n")
            git(large, "add", *[f"file-{n:05}" for n in range(1000)])
            for n in range(200):
                (large / f"untracked-{n:05}").write_text("untracked\n")
            report["cases"][dirty_case] = measure(commands, large, args.samples, args.startup_samples)
            print(f"Measured {dirty_case}", file=sys.stderr, flush=True)
    print(json.dumps(report, indent=2))


if __name__ == "__main__":
    main()
