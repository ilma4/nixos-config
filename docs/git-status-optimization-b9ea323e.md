# Git-status optimization against b9ea323e

Measured on 2026-10-02 against `b9ea323e0c597bd848d72377e37752b95e11af0d`.
Apple M3 Max, 64 GiB RAM, macOS 26.7.1, Git 2.55.0, Zsh 5.9.1.
Both workers and allocator probes were built with the flake's Rust 1.95.0,
edition 2021, `-C opt-level=3 -C strip=symbols`, through `runCommandCC`.
The installed Rust 1.98.1 was not used for the worker comparisons.

The client uses an integer environment counter and handles failed, stale and
current replies in one conditional. The worker reuses the status-line and three
header buffers and copies header values into existing capacity. It also handles
detached headers and expected I/O shutdowns with shorter conditionals.

The byte-length protocol, twelve response fields, exact Git command order and
arguments, PATH and exported `GIT_*` forwarding, redraws, stale requests, single
worker lifetime and failure cleanup remain unchanged. The measurement session
did not commit or switch configurations.

## Source size

| Source | Before lines | After lines | Difference |
| --- | --- | --- | --- |
| Client | 119 | 116 | -3 |
| Worker | 203 | 201 | -2 |
| Total | 322 | 317 | -5 (-1.6%) |

Counts are physical source lines, including comments and blank lines. Source and
binary hashes and compiler metadata are saved with the raw measurements.

## Client CPU and peak RSS

Fifteen randomized pairs of fresh Zsh processes using compiled clients. Each
process runs 50,000 precmd calls, 10,000 sends or replies, or 3,000 sends with 100
additional exported Git variables. Precmd stubs sends; sends write to `/dev/null`;
replies use a prepared response file and stub redraws. No worker or Git child runs.
`wait4` records user plus system CPU and peak shell RSS, with startup amortized.

| Workload | Before CPU µs/call | After CPU µs/call | Change | Paired 95% interval | Before/after peak RSS KiB |
| --- | --- | --- | --- | --- | --- |
| precmd | 8.34 | 8.34 | +0.1% | -1.4% to +1.2% | 3424 / 3424 |
| precmd-cd | 10.13 | 10.15 | +0.2% | -1.2% to +1.0% | 3424 / 3424 |
| send | 63.42 | 63.92 | +0.8% | -1.7% to +1.7% | 3440 / 3440 |
| send-many | 264.93 | 260.77 | -1.6% | -3.2% to +1.9% | 3712 / 3712 |
| response | 44.97 | 44.41 | -1.2% | -3.2% to +1.6% | 3472 / 3472 |

## Rust allocation traffic and peak live heap

The probes delegate to `System` and count 100 requests, including process startup
and shutdown. Figures exclude allocator metadata, stacks, direct C allocations
and all child processes. Allocation traffic is cumulative, not resident memory;
peak live heap includes the startup environment scan.

| Environment/repository | Before/after allocations/request | Before/after allocated KiB/request | Before/after peak heap KiB |
| --- | --- | --- | --- |
| checkout | 38.02 / 37.03 | 5.336 / 5.297 | 35.728 / 35.728 |
| named_branch | 40.01 / 38.03 | 5.589 / 5.547 | 35.728 / 35.728 |
| 100_git_variables | 3027.08 / 3026.09 | 357.756 / 357.718 | 104.345 / 104.353 |
| changed_path | 1433.02 / 1432.03 | 277.067 / 277.028 | 71.681 / 71.688 |
| alternating_path | 735.53 / 734.54 | 141.266 / 141.227 | 74.898 / 74.906 |

The named-branch fixture saves approximately two allocations per request after
warmup. The detached checkout saves approximately one, because it has no branch
name to allocate. These counts are deterministic for the tested request streams;
they do not establish lower RSS. Reusable buffers retain their maximum observed
capacity until worker exit, so unusually long headers can increase retained heap.

## Live worker CPU and RSS

Seven fresh worker pairs per environment, five warmups and 30 requests per
worker, randomized request order. `proc_pid_rusage` V0 measures only each worker
PID, excluding Git children. Mach CPU units are converted using
`mach_timebase_info`, with a self-CPU calibration against `getrusage`.
RSS is each process's median of three snapshots, then the median of seven
processes; ranges show those seven process medians.

| Environment | Before/after CPU µs/request | Change | 95% interval | Before/after RSS KiB | Before/after RSS ranges KiB |
| --- | --- | --- | --- | --- | --- |
| checkout | 6344.64 / 6279.68 | -1.0% | -1.8% to +1.8% | 1936 / 1936 | 1888-1984 / 1920-1984 |
| one_git_variable | 6546.40 / 6546.56 | +0.0% | -2.8% to +1.1% | 2528 / 2384 | 2512-2544 / 2368-2624 |
| 100_git_variables | 7066.73 / 7093.41 | +0.4% | -2.0% to +3.9% | 2592 / 2432 | 2560-2624 / 2400-2496 |
| changed_path | 1576.98 / 1552.12 | -1.6% | -4.3% to -0.5% | 2480 / 2368 | 2464-2560 / 2304-2576 |
| alternating_path | 4161.17 / 4093.37 | -1.6% | -3.9% to +1.6% | 2544 / 2432 | 2528-2608 / 2384-2656 |

## Controlled parser component

The same C fixture executable emits prepared porcelain records. It is first in
both workers' inherited PATH. Seven fresh worker pairs, five warmups and 50
requests per worker, randomized order and byte-for-byte response assertions.
CPU and RSS use the worker-PID measurement above and exclude fixture children.

| Stream | Before/after CPU µs/request | Change | 95% interval | Before/after RSS KiB |
| --- | --- | --- | --- | --- |
| headers | 1151.03 / 1133.16 | -1.6% | -4.7% to -0.8% | 1920 / 1968 |
| tracked_5000 | 1438.71 / 1453.01 | +1.0% | -2.2% to +3.1% | 1920 / 1952 |
| untracked_5000_long | 1503.47 / 1542.05 | +2.6% | -2.0% to +5.6% | 1952 / 1968 |

## Complete Git latency

Two persistent workers, ten warmups and 100 randomized paired requests per
repository. Every response is compared byte for byte. Times include IPC and
all Git children. Fixtures disable fsmonitor and untracked caching. The dirty
fixture stages 1,000 of 5,000 modifications and adds 200 untracked files. The
checkout case uses the same working tree for both executables.

| Repository | Before median/p95 ms | After median/p95 ms | Change | 95% interval |
| --- | --- | --- | --- | --- |
| non_repo | 11.33 / 14.78 | 11.59 / 15.54 | +2.3% | -0.5% to +5.3% |
| small_clean_10_files | 42.23 / 47.46 | 42.55 / 47.10 | +0.8% | -1.7% to +4.1% |
| checkout | 54.14 / 62.19 | 55.03 / 61.52 | +1.7% | -0.9% to +3.6% |
| large_clean_5000_files | 52.49 / 56.67 | 52.60 / 57.19 | +0.2% | -1.6% to +2.3% |
| large_dirty_5000_modified_200_untracked | 277.50 / 293.25 | 277.49 / 293.54 | -0.0% | -0.8% to +0.7% |

Ten fresh-process first-response samples per version and case:

| Repository | Before startup median ms | After startup median ms |
| --- | --- | --- |
| non_repo | 17.35 | 17.61 |
| small_clean_10_files | 51.31 | 52.72 |
| checkout | 60.26 | 59.41 |
| large_clean_5000_files | 59.43 | 59.71 |
| large_dirty_5000_modified_200_untracked | 280.06 | 283.04 |

RSS during 1,000 named-branch requests alternating inherited and changed PATH:

| Request | Before RSS KiB | After RSS KiB |
| --- | --- | --- |
| 5 | 2304.0 | 2256.0 |
| 100 | 2544.0 | 2448.0 |
| 500 | 2448.0 | 2352.0 |
| 1000 | 2448.0 | 2352.0 |

## Uncertainty and limits

Intervals are paired percentile bootstrap intervals for the change in medians:
10,000 resamples of process pairs (component CPU) or request pairs (complete
latency), fixed seed 8675309. They describe these samples on this shared machine;
small process counts, within-process correlation, shared filesystem caches,
scheduler activity and multiple comparisons limit inference. Startup has only
ten observations per version. Peak RSS and current RSS are distinct metrics,
and macOS page accounting makes small RSS differences coarse and variable.

Allocator savings are established. CPU/latency and RSS conclusions must be
workload-specific; a small median change or an interval spanning zero supports
no speedup claim. Memory measurements cover the client/worker, not transient Git
children. The optimization does not establish a general end-to-end or resident
memory improvement.

The rejected parameter-table lookup made 100-variable client sends 19.4% slower
in the initial nine-pair trial. Its source and raw report are retained separately.

## Behavior validation

- Both final versions pass all 21 daemon tests and four client tests. The added
  regression checks long-to-short headers, replacement of duplicate headers,
  detached/unborn requests and clearing state after failed Git status.
  The final Nix-packaged worker/client also pass these suites and render the
  branch through actual Powerlevel10k.
- A saved raw-protocol differential suite passes 19 scenarios; another harness
  passes 27 comparisons including a stream of 100 varied replies, control bytes,
  Unicode, NULs, environment types, malformed input and response sizes.
- Thirty PATH search/recovery streams and 150 randomized malformed/raw-byte
  porcelain streams match baseline. Exact Git argv, command order, environment,
  upstream/tag selection, operation precedence, stash, reftable, worktrees,
  conflicts and branch divergence are checked.
- PTY tests cover asynchronous readiness, stale replies, duplicate launches,
  directory changes, foreground commands, worker failure and cleanup. Both
  versions render the branch through actual Powerlevel10k in a generated shell.
- `zsh -n`, `rustfmt --check`, Nix worker/generated Quicksilver `.zshrc` builds and
  `./utils/flake-check.sh` pass. The flake check ran before and after edits.
- mcp-nixos confirms the existing `rustc` and `zsh` packages. No options or
  dependencies were added.

## Commands and artifacts

All scratch files, fixture repositories, logs, source snapshots, instrumented
probes, harnesses and raw samples are under:

`/Users/ilma4/.config/nixos-config/tmp/improve-git-status.iGyoz0/1/`

Fixtures live beneath an invalid `.git` marker in that scratch directory to stop
non-repository tests from discovering the enclosing nixos-config repository.
This marker affects only fixture ancestry; the checkout workload is outside it.
`TMPDIR`, shell history/completion/cache paths and Python bytecode handling keep
test-generated scratch artifacts there.

Commands run from the checkout (the scripts contain the exact individual commands):

```bash
set -euo pipefail
artifact_dir="$PWD/tmp/improve-git-status.iGyoz0/1"
jj status
jj file show -r b9ea323e0c597bd848d72377e37752b95e11af0d home/git-status-client.zsh > "$artifact_dir/baseline-client.zsh"
jj file show -r b9ea323e0c597bd848d72377e37752b95e11af0d home/git-status-daemon.rs > "$artifact_dir/baseline-daemon.rs"
./utils/flake-check.sh
nix build --impure --no-link --json --file "$artifact_dir/build-probes.nix"
nix build --no-link --json '.#darwinConfigurations.quicksilver.config.home-manager.users.ilma4.home.file."./.zshrc".source'
zsh -n home/git-status-client.zsh
rustfmt --check --edition 2021 home/git-status-daemon.rs
bash "$artifact_dir/validate.sh"
bash "$artifact_dir/benchmark.sh"
python3 "$artifact_dir/report.py"
wc -l home/git-status-client.zsh home/git-status-daemon.rs
jj diff --stat
jj status
```

The latency command within `benchmark.sh` is:

```bash
set -euo pipefail
artifact_dir="$PWD/tmp/improve-git-status.iGyoz0/1"
TMPDIR="$artifact_dir" PYTHONDONTWRITEBYTECODE=1 \
  python3 tests/benchmark-git-status-daemon.py \
  --baseline "$artifact_dir/before" --baseline-raw \
  --native "$artifact_dir/after" --samples 100 --startup-samples 10
```

`metadata.json` identifies the baseline and final source hashes. `micro.json`
contains client CPU/peak RSS and Rust allocator results; `native-resources.json`
contains live worker CPU/RSS; `parser-component.json` contains fixture CPU/RSS;
`daemon.json` contains full-request/startup samples; `long-memory.json` contains
the lifetime RSS snapshots; `uncertainty.json` contains the calculated intervals.
Earlier exploratory measurements use `initial-*`, `client-experiment.json` and
`rejected-parameter-table-micro.json` and are not the final benchmark results.

## Independent review

The review matched baseline snapshots to the specified Jujutsu revision and
verified SHA-256 hashes of current sources and all measured executables. It
recomputed the header CPU medians and bootstrap interval from raw samples.
A fresh 100-request named-branch allocator run measured 3,999 versus 3,801
allocations and 580,468 versus 576,116 allocated bytes: the same savings of
198 allocations and 4,352 bytes as the original run. Absolute counts and peak
heap differed with the review environment; peak heap was equal between versions.
The review reran the complete validation script, including both versions'
daemon/client suites, differential and malformed-stream checks, PTY lifecycle,
Powerlevel10k, syntax, formatting and flake checks, and rebuilt the generated
Quicksilver shell. The allocation reduction justifies the change; no general
latency or RSS improvement is claimed.
