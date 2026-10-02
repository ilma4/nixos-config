# Git-status optimization against 638fdba5

Measured on 2026-10-02 against `638fdba5f45f3c19e6a3c8de5b774959f0916318`.
Apple M3 Max, 64 GiB RAM, macOS 26.7.1, Git 2.55.0, Zsh 5.9.1.
Both workers and allocator probes were built with the flake's Rust 1.95.0,
edition 2021, `-C opt-level=3 -C strip=symbols`, through `runCommandCC`.
The installed Rust 1.98.1 was not used for the worker comparisons.

The worker reuses its cleared status-line buffer for the upstream lookup key,
removing a temporary allocation, and uses a shorter inherited-variable cleanup
iterator. The client resets its inflight flag once at response entry.
An added regression tests changing long, short, empty and raw-byte branch names
and an unterminated final status record during repeated upstream lookups.

Live measurements use the final Nix-packaged worker after the change. Baseline
and instrumented probes use matching snapshots and the same compiler/flags.
Binary identities are recorded separately: embedded Rust source paths can make
packaged and probe executables differ. Client CPU uses compiled source snapshots.

The byte-length protocol, twelve response fields, exact Git command order and
arguments, PATH and exported `GIT_*` forwarding, redraws, stale requests, single
worker lifetime and failure cleanup remain unchanged. No commit or configuration
switch was performed.

## Source size

| Source | Before lines | After lines | Difference |
| --- | --- | --- | --- |
| Client | 116 | 115 | -1 |
| Worker | 201 | 199 | -2 |
| Total | 317 | 314 | -3 (-0.9%) |

Counts are physical source lines, including comments and blank lines. Added tests and this report are excluded. Source and
binary hashes and compiler metadata are saved with the raw measurements.

## Client CPU and peak RSS

Fifteen randomized pairs of fresh Zsh processes using compiled clients. Each
process runs 50,000 precmd calls, 10,000 sends or replies, or 3,000 sends with 100
additional exported Git variables. Precmd stubs sends; sends write to `/dev/null`;
replies use a prepared response file and stub redraws. No worker or Git child runs.
`wait4` records user plus system CPU and peak shell RSS, with startup amortized.

| Workload | Before CPU µs/call | After CPU µs/call | Change | Paired 95% interval | Before/after peak RSS KiB |
| --- | --- | --- | --- | --- | --- |
| precmd | 8.80 | 9.04 | +2.7% | -0.5% to +5.2% | 3312 / 3296 |
| precmd-cd | 11.04 | 10.76 | -2.6% | -5.8% to +4.4% | 3312 / 3296 |
| send | 69.78 | 69.57 | -0.3% | -1.7% to +1.2% | 3328 / 3328 |
| send-many | 271.16 | 267.30 | -1.4% | -3.2% to +2.6% | 3600 / 3600 |
| response | 47.32 | 46.99 | -0.7% | -1.3% to -0.1% | 3360 / 3376 |

## Rust allocation traffic and peak live heap

The probes delegate to `System` and count 100 requests, including process startup
and shutdown. Figures exclude allocator metadata, stacks, direct C allocations
and all child processes. Allocation traffic is cumulative, not resident memory;
peak live heap includes the startup environment scan.

| Environment/repository | Before/after allocations/request | Before/after allocated KiB/request | Before/after peak heap KiB |
| --- | --- | --- | --- |
| checkout | 37.03 / 37.03 | 5.294 / 5.294 | 35.626 / 35.626 |
| named_branch | 50.04 / 49.04 | 5.796 / 5.779 | 35.626 / 35.626 |
| 100_git_variables | 3026.09 / 3026.09 | 357.106 / 357.106 | 104.077 / 104.077 |
| changed_path | 1432.03 / 1432.03 | 275.895 / 275.895 | 71.326 / 71.326 |
| alternating_path | 734.54 / 734.54 | 140.657 / 140.657 | 74.457 / 74.457 |

The tracking-branch fixture uses origin/main. It saves exactly 100 allocations
and 1,800 allocated bytes over 100 requests: one allocation and 18 bytes per
request. The detached checkout has no upstream lookup and saves no allocations.
Ordinary peak heap is unchanged. These counts are deterministic for the tested
streams and do not establish lower RSS. Reusing the existing status-line capacity
adds no retained capacity: the branch header is at least as long as its lookup key.

## Live worker CPU and RSS

Seven fresh worker pairs per environment, five warmups and 30 requests per
worker, randomized request order. `proc_pid_rusage` V0 measures only each worker
PID, excluding Git children. Mach CPU units are converted using
`mach_timebase_info`, with a self-CPU calibration against `getrusage`.
RSS is each process's median of three snapshots, then the median of seven
processes; ranges show those seven process medians.

| Environment | Before/after CPU µs/request | Change | 95% interval | Before/after RSS KiB | Before/after RSS ranges KiB |
| --- | --- | --- | --- | --- | --- |
| checkout | 7145.27 / 7106.52 | -0.5% | -4.0% to +0.7% | 1952 / 1936 | 1904-1968 / 1888-1968 |
| one_git_variable | 6664.04 / 6808.25 | +2.2% | -0.7% to +2.5% | 2512 / 2336 | 2464-2544 / 2304-2576 |
| 100_git_variables | 6627.01 / 6745.57 | +1.8% | -2.2% to +1.9% | 2576 / 2576 | 2544-2592 / 2384-2608 |
| changed_path | 1357.28 / 1350.18 | -0.5% | -7.7% to +1.3% | 2480 / 2480 | 2464-2512 / 2256-2528 |
| alternating_path | 3910.02 / 3859.89 | -1.3% | -3.8% to -0.1% | 2528 / 2336 | 2496-2560 / 2288-2544 |

## Controlled parser component

The same C fixture executable emits prepared porcelain records. It is first in
both workers' inherited PATH. Seven fresh worker pairs, five warmups and 50
requests per worker, randomized order and byte-for-byte response assertions.
CPU and RSS use the worker-PID measurement above and exclude fixture children.

| Stream | Before/after CPU µs/request | Change | 95% interval | Before/after RSS KiB |
| --- | --- | --- | --- | --- |
| headers | 2293.27 / 2258.37 | -1.5% | -5.3% to +2.3% | 1968 / 1952 |
| upstream_headers | 3207.61 / 3105.75 | -3.2% | -7.4% to +1.1% | 1968 / 1952 |
| tracked_5000 | 2649.51 / 2615.79 | -1.3% | -4.5% to +5.2% | 1968 / 1952 |
| untracked_5000_long | 2831.24 / 2814.62 | -0.6% | -3.5% to +4.6% | 1984 / 1952 |

## Complete Git latency

Two persistent workers, ten warmups and 100 randomized paired requests per
repository. Every response is compared byte for byte. Times include IPC and
all Git children. Fixtures disable fsmonitor and untracked caching. The dirty
fixture stages 1,000 of 5,000 modifications and adds 200 untracked files. The
checkout case uses the same working tree for both executables.

| Repository | Before median/p95 ms | After median/p95 ms | Change | 95% interval | Before/after worker RSS KiB |
| --- | --- | --- | --- | --- | --- |
| non_repo | 10.15 / 12.32 | 10.33 / 13.13 | +1.8% | -1.4% to +3.7% | 1888 / 1896 |
| small_clean_10_files | 41.01 / 45.60 | 40.53 / 46.13 | -1.2% | -2.8% to +1.7% | 1904 / 1960 |
| checkout | 52.16 / 56.51 | 52.49 / 58.27 | +0.6% | -2.5% to +3.2% | 1944 / 1912 |
| large_clean_5000_files | 51.78 / 56.06 | 51.50 / 55.78 | -0.5% | -2.7% to +0.5% | 1968 / 2016 |
| large_dirty_5000_modified_200_untracked | 333.39 / 368.88 | 332.04 / 356.68 | -0.4% | -1.2% to +0.4% | 1928 / 1976 |

Ten fresh-process first-response samples per version and case:

| Repository | Before startup median ms | After startup median ms |
| --- | --- | --- |
| non_repo | 14.83 | 15.92 |
| small_clean_10_files | 48.84 | 48.94 |
| checkout | 64.75 | 64.05 |
| large_clean_5000_files | 59.93 | 57.96 |
| large_dirty_5000_modified_200_untracked | 340.42 | 341.79 |

RSS during 1,000 named-branch requests alternating inherited and changed PATH:

| Request | Before RSS KiB | After RSS KiB |
| --- | --- | --- |
| 5 | 2448.0 | 2448.0 |
| 100 | 2528.0 | 2608.0 |
| 500 | 2528.0 | 2608.0 |
| 1000 | 2528.0 | 2608.0 |

## Isolated upstream-key construction CPU

The exact key-construction statements from each source run in a standalone Rust
probe, with preallocated status-line capacity and black_box consumption of each
key. Fifteen randomized fresh-process pairs per length; one million iterations
per process. wait4 measures user plus system CPU, amortizing startup. This
isolates key creation/freeing, excluding Git/IPC. Peak RSS includes process startup.
The 8 KiB branch is a synthetic stress case, not a representative repository.

| Branch bytes | Before CPU ns/key | After CPU ns/key | Change | Paired 95% interval | Before/after peak RSS KiB |
| --- | --- | --- | --- | --- | --- |
| 4 | 19.70 | 4.05 | -79.4% | -79.8% to -78.8% | 1632 / 1584 |
| 240 | 19.08 | 18.22 | -4.5% | -6.2% to -2.7% | 1616 / 1584 |
| 8192 | 154.35 | 164.00 | +6.2% | +2.1% to +11.3% | 1648 / 1632 |

The ordinary four-byte key is faster. The 8 KiB key is slightly slower in the
isolated CPU measurement, while saving temporary heap. This tradeoff is confined
to key construction; complete Git latency is dominated by subprocesses.

## Synthetic-header heap

The C fixture supplies controlled headers, without placing the headers in the
worker environment. System allocator probes process 100 requests and compare
every reply byte for byte. Long synthetic headers stress capacities only.

| Branch bytes | Allocation change/request | Allocated-byte change/request | Before/after peak live heap KiB |
| --- | --- | --- | --- |
| 4 | -1.0 | -18.0 | 35.794 / 35.794 |
| 240 | -1.0 | -254.0 | 35.794 / 35.794 |
| 8192 | -1.0 | -8206.0 | 76.338 / 68.324 |
| 65536 | -1.0 | -65550.0 | 468.338 / 404.324 |

## Uncertainty and limits

Intervals are paired percentile bootstrap intervals for the change in medians:
10,000 resamples of process pairs (component CPU) or request pairs (complete
latency), fixed seed 8675309. They describe these samples on this shared machine;
small process counts, within-process correlation, shared filesystem caches,
thermal/frequency variation, changes in unchanged control paths,
scheduler activity and multiple comparisons limit inference. Startup has only
ten observations per version. Peak RSS and current RSS are distinct metrics,
and macOS page accounting makes small RSS differences coarse and variable.

Allocator savings are established. CPU/latency and RSS conclusions must be
workload-specific; a small median change or an interval spanning zero supports
no speedup claim. Memory measurements cover the client/worker, not transient Git
children. The optimization does not establish a general end-to-end or resident
memory improvement.

The rejected client experiment cached each indirect environment value.
Its 100-variable send median changed 265.18 to 285.22 microseconds (+7.6%),
added a line and increased peak shell RSS from 3632 to 3648 KiB. It was discarded;
cached-value.zsh and client-experiment.json retain its source and nine paired runs.

## Behavior validation

- Both versions pass all 22 daemon tests and four client tests. The new upstream
  regression also passes against the unchanged baseline. It covers repeated
  config-key construction with long-to-short, empty and non-UTF-8 headers and an
  unterminated last status record. The final Nix-packaged worker/client also pass
  the suites and render the branch through actual Powerlevel10k.
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

`/Users/ilma4/.config/nixos-config/tmp/improve-git-status.050y7L/1/`

Fixtures live beneath an invalid `.git` marker in that scratch directory to stop
non-repository tests from discovering the enclosing nixos-config repository.
This marker affects only fixture ancestry; the checkout workload is outside it.
`TMPDIR`, shell history/completion/cache paths and Python bytecode handling keep
test-generated scratch artifacts there.

Commands run from the checkout (the scripts contain the exact individual commands):

```bash
set -euo pipefail
artifact_dir="$PWD/tmp/improve-git-status.050y7L/1"
jj status
jj file show -r 638fdba5f45f3c19e6a3c8de5b774959f0916318 home/git-status-client.zsh > "$artifact_dir/baseline-client.zsh"
jj file show -r 638fdba5f45f3c19e6a3c8de5b774959f0916318 home/git-status-daemon.rs > "$artifact_dir/baseline-daemon.rs"
./utils/flake-check.sh
nix build --impure --no-link --json --file "$artifact_dir/build-probes.nix"
nix build --no-link --json '.#darwinConfigurations.quicksilver.config.home-manager.users.ilma4.home.file."./.zshrc".source'
python3 "$artifact_dir/prepare-final.py"
zsh -n home/git-status-client.zsh
rustfmt --check --edition 2021 home/git-status-daemon.rs
bash "$artifact_dir/validate.sh"
python3 "$artifact_dir/micro.py"
bash "$artifact_dir/benchmark.sh" --remaining
python3 "$artifact_dir/report.py"
wc -l home/git-status-client.zsh home/git-status-daemon.rs
jj diff --stat
jj status
```

The latency command within `benchmark.sh` is:

```bash
set -euo pipefail
artifact_dir="$PWD/tmp/improve-git-status.050y7L/1"
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
The isolated key and synthetic-header heap reports are in key-component.json
and upstream-memory.json. Exploratory client-experiment.json is separate from
final measurements. final-build.sh records the final build/validation sequence.

## Independent review

The review verified the baseline snapshots against `jj file show`, current source
against the measured snapshots, and executable SHA-256 hashes against metadata.
Raw key and latency sample counts and medians match the report; independently
recomputed paired bootstrap intervals match `uncertainty.json`.

Rerunning `validate.sh` passed both versions' 22 daemon and four client tests,
19 differential-suite scenarios, 27 differential checks, 30 PATH comparisons,
150 malformed/raw-byte streams, PTY lifecycle checks, actual Powerlevel10k
rendering, syntax, formatting and the flake check. A fresh 100-request tracking
branch allocator run again saved exactly 100 allocations and 1,800 allocated
bytes, with identical responses and unchanged peak live heap within that pair.
Absolute allocation totals differ with the review process environment.

The retained improvement is the removed temporary allocation and smaller source.
The synthetic 8 KiB key's approximately 10 ns construction slowdown is immaterial
relative to complete requests measured in milliseconds. No general latency or RSS
improvement is claimed.
