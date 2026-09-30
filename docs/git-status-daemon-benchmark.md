# Rust Git status worker comparison

Measured on 2026-09-30, Apple M3 Max, macOS 26.7.1, Git 2.55.0,
Zsh 5.9.1. The Rust worker was built by the Quicksilver Home Manager
derivation with the flake's Rust 1.95.0, optimization level 3 and stripped
symbols. The baseline is the original `home/git-status-daemon.zsh` from
commit `503c307c`.

The worker still launches Git in the same order with the same arguments:
`status`, `config --get branch.<branch>.remote` when tracking an upstream,
`tag --points-at HEAD --sort=refname`, and `rev-parse --absolute-git-dir`.
Only `status` overrides `GIT_OPTIONAL_LOCKS=0`. The quoted line request
protocol, twelve status fields, per-request PATH and exported Git variables,
operation detection and asynchronous client lifecycle are preserved. No Git
library or external Rust dependency is used.

## Warm request latency and memory

Each case uses two persistent workers, ten warmup requests, then 100 measured
requests per worker. Worker order is randomized within each pair with a fixed
seed; every response is checked for byte-for-byte equality. Short cases were
repeated after the test suite completed. The large fixture has 5,000 tracked
files; the dirty case stages 1,000 modifications, leaves 4,000 unstaged, and
adds 200 untracked files. Synthetic repositories disable fsmonitor and the
untracked cache. Git configuration in the actual checkout is retained.

Times include pipe IPC, Git subprocesses and formatting. RSS is the median of
ten `ps -o rss` readings taken after responses, converted from KiB to MiB.
It measures resident worker memory, including shared pages; it excludes
transient Git processes and does not measure peak memory during a request.

| Case | Zsh median / p95 (ms) | Rust median / p95 (ms) | Latency reduction | Zsh RSS (MiB) | Rust RSS (MiB) |
| --- | ---: | ---: | ---: | ---: | ---: |
| Outside a repository | 14.39 / 17.07 | 11.67 / 13.48 | 18.9% | 3.34 | 2.55 |
| Clean repository, 10 files | 49.40 / 53.23 | 42.43 / 46.82 | 14.1% | 3.39 | 2.58 |
| This checkout | 55.11 / 59.87 | 48.35 / 53.73 | 12.3% | 3.61 | 2.66 |
| Clean repository, 5,000 files | 58.33 / 62.76 | 51.06 / 54.99 | 12.5% | 3.44 | 2.62 |
| Dirty repository, 5,000 modified files + 200 untracked | 579.90 / 611.00 | 321.71 / 355.45 | 44.5% | 7.62 | 3.97 |

In this checkout, the Rust worker uses 26.4% less resident memory and returns
status 12.3% sooner. In the large dirty fixture, resident memory drops 48.0%
and responses are 1.80 times as fast. Absolute timings depend on repository
shape, Git configuration, filesystem caches and machine load.

## Worker startup

Thirty new processes per implementation and case, with randomized paired
order. These are warm-cache measurements from before process creation until
the first complete response; process shutdown is excluded.

| Case | Zsh median (ms) | Rust median (ms) |
| --- | ---: | ---: |
| Outside a repository | 29.40 | 19.66 |
| Clean repository, 10 files | 64.23 | 50.10 |
| This checkout | 70.23 | 54.89 |
| Clean repository, 5,000 files | 74.69 | 58.58 |
| Dirty repository, 5,000 modified files + 200 untracked | 594.36 | 330.38 |

The client requests status asynchronously. These measurements describe when
Git status becomes available; they are not interactive shell startup, typing
lag, or prompt command lag measurements.

## Reproduce

Save the original worker from Jujutsu and run the comparison. Without
`--native`, the script compiles the Rust source using the Rust compiler in
PATH. To measure the Nix package, pass its worker path explicitly as below.
The script emits JSON with all raw timing and RSS samples. `--case` can be
repeated to select workloads.

```bash
set -euo pipefail
jj file show -r 503c307c home/git-status-daemon.zsh > /tmp/git-status-legacy.zsh
python3 tests/benchmark-git-status-daemon.py \
  --legacy /tmp/git-status-legacy.zsh \
  --native /nix/store/vjshakf72pyqlq58k80ycspsj4q4sjm4-i4-git-status-daemon/git-status-daemon \
  > /tmp/git-status-benchmark.json
```

The Nix output path changes when its source or inputs change. The path above
identifies the exact binary measured for this report.

## Validation

`./utils/flake-check.sh` passed for all configured systems. The Quicksilver
worker derivation built successfully and produced an arm64 Mach-O binary.
Seventeen daemon tests passed using that binary and the original Zsh worker
as a comparison. They cover status counts, conflict, stash, detached and
unborn HEAD, tags, divergence, remote names, renames, reftable, worktrees and
operation precedence, control-byte paths, arbitrary environment bytes,
C/UTF-8 quoting, per-request environment/PATH changes, command arguments and
lock handling, non-repositories and incomplete requests.

Both PTY lifecycle tests passed using the native binary and the packaged
client, including its compiled Zsh file: the worker remains running across
directory changes and foreground commands, duplicate startup is refused,
and an exited worker is reported once without being restarted. Configuration
was not activated.
