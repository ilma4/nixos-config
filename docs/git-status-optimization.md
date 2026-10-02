# Git status client and daemon optimization

Measured on 2026-10-02 on Apple M3 Max, macOS 26.7.1, Git 2.55.0 and Zsh 5.9.1. Baseline: `71f4ae33e919454e592d56a27ce294737a1358bb`. Both packaged workers and allocation probes use the flake’s Rust 1.95.0, edition 2021, optimization level 3 and stripped symbols. The locally installed Rust 1.98.1 was not used for the reported worker comparisons.

The parser dispatches on the first porcelain token and reads additional fields only for headers. File counts no longer require scanning filename fields. The client simplifies directory-change cache invalidation; the worker also simplifies successful-exit checks, operation-marker metadata checks and number parsing.

Git command order and arguments, PATH and exported Git variables, byte-length framing, all twelve response fields, asynchronous redraws, stale replies, worker lifetime and failure cleanup are preserved.

| Source | Before | After |
| --- | ---: | ---: |
| Client | 120 lines | 119 lines |
| Worker | 208 lines | 206 lines |
| Total | 328 lines | 325 lines (-0.9%) |

## Controlled parser CPU

The same C fixture executable emits prepared porcelain records instead of scanning a repository. It is first in the inherited PATH for both workers. Seven fresh worker pairs per workload, five warmups and 50 requests per worker, with randomized request order and byte-for-byte reply checks. CPU is user plus system time from `proc_pid_rusage` for the worker PID, excluding fixture children and startup; Mach time units are converted with `mach_timebase_info`.

| Stream | Before CPU (µs/request) | After CPU (µs/request) | Change |
| --- | ---: | ---: | ---: |
| headers | 1061.42 | 1060.37 | -0.1% |
| tracked_5000 | 1347.24 | 1358.41 | +0.8% |
| untracked_5000_long | 2019.58 | 1410.48 | -30.2% |

The stream with 5,000 untracked records and 180-byte names uses 30.2% less worker CPU. Header-only and tracked-file results are essentially unchanged. This is a component improvement; complete Git latency below does not improve consistently.

## Client CPU and peak RSS

Nine randomized before/after pairs in fresh Zsh processes using compiled clients. Each pair runs 50,000 precmd calls, 10,000 sends or responses, or 3,000 sends with 100 extra Git variables. Precmd uses a stub send, sends write to `/dev/null`, and responses read a prepared file with redraws stubbed. No worker or Git children are launched. `wait4` supplies CPU and peak shell RSS; startup is amortized.

| Workload | Before CPU (µs/call) | After CPU (µs/call) | Change | Before/after peak RSS (KiB) |
| --- | ---: | ---: | ---: | ---: |
| precmd | 12.58 | 12.57 | -0.1% | 3520 / 3536 |
| precmd-cd | 16.24 | 15.43 | -5.0% | 3616 / 3616 |
| send | 119.02 | 123.33 | +3.6% | 3536 / 3616 |
| send-many | 415.91 | 423.99 | +1.9% | 3824 / 3920 |
| response | 64.36 | 66.13 | +2.7% | 3648 / 3568 |

Small client differences are inconclusive. Paired bootstrap intervals for both precmd workloads include zero, and unchanged send/response controls vary by several percent. No interactive shell speedup is established.

## Worker memory and checkout CPU

Rust allocator probes delegate to `System` and count 100 requests including startup and shutdown. Allocation traffic and peak live heap exclude allocator metadata, stacks, direct C allocations and child processes. Before and after allocation figures are exactly equal in every measured case.

| Request environment | Allocations/request, both | Allocated KiB/request, both | Peak live Rust heap (KiB), both |
| --- | ---: | ---: | ---: |
| checkout | 38.00 | 5.44 | 44.70 |
| 100_git_variables | 3009.06 | 406.58 | 113.51 |
| changed_path | 1424.00 | 335.99 | 83.17 |
| alternating_path | 731.01 | 170.80 | 87.22 |

Actual packaged-worker CPU and RSS use seven fresh process pairs per case, five warmups and 30 randomized paired checkout requests. Every reply is checked for byte equality and twelve fields. RSS is the median of each process’s three snapshots, followed by the median of seven processes. Ranges below are the seven process medians. `proc_pid_rusage` measures only the launched worker PIDs, excluding Git children.

| Request environment | Before/after CPU (µs/request) | Change | Before/after RSS (KiB) | Before/after RSS ranges (KiB) |
| --- | ---: | ---: | ---: | ---: |
| checkout | 8102.62 / 7982.63 | -1.5% | 1904 / 1904 | 1904-1936 / 1888-1936 |
| one_git_variable | 8428.73 / 8388.26 | -0.5% | 2592 / 2608 | 2240-2640 / 2272-2640 |
| 100_git_variables | 7886.23 / 7941.90 | +0.7% | 2656 / 2656 | 2256-2672 / 2272-2672 |
| changed_path | 1176.44 / 1168.42 | -0.7% | 2560 / 2560 | 2528-2608 / 2528-2592 |
| alternating_path | 4191.99 / 4274.69 | +2.0% | 2576 / 2576 | 2560-2640 / 2560-2624 |

No general CPU or resident-memory improvement is established for these checkout cases. All RSS ranges overlap. In a separate 1,000-request run alternating PATH values outside a repository, RSS stabilized by request 100 at 2,576 / 2,640 KiB and stayed unchanged at requests 500 and 1,000.

## Complete Git request latency

Two persistent packaged workers, ten warmups, then 100 randomized paired requests per repository; every response is checked for byte equality. Times include IPC and all Git subprocesses. Fixtures disable fsmonitor and the untracked cache. The dirty fixture stages 1,000 of 5,000 modifications and adds 200 untracked files. Ten fresh-process first-response samples per version and case are also stored in the raw report.

| Repository | Before median/p95 (ms) | After median/p95 (ms) | Median change |
| --- | ---: | ---: | ---: |
| non_repo | 10.25 / 12.35 | 10.36 / 13.72 | +1.1% |
| small_clean_10_files | 39.57 / 46.00 | 39.04 / 45.61 | -1.3% |
| checkout | 45.88 / 50.84 | 46.30 / 52.06 | +0.9% |
| large_clean_5000_files | 48.00 / 53.33 | 47.73 / 51.69 | -0.6% |
| large_dirty_5000_modified_200_untracked | 264.50 / 298.74 | 264.25 / 290.53 | -0.1% |

Complete-request medians change by -1.3% to +1.1%, without a consistent improvement. The retained optimization reduces parser CPU for long untracked listings; it does not establish lower full-Git latency or memory consumption.

## Rejected experiments

Inheriting changed PATH values reduced allocation traffic and RSS, but increased changed-PATH worker CPU from 1,235 to 7,318 µs/request on this macOS setup. A 2,048-byte status buffer increased tracked-fixture CPU by 5.8%; a 1,024-byte buffer increased it by 18.7%. These changes were discarded. The original PATH forwarding and 4,096-byte read buffer remain. Unused environment-buffer retention was also discarded because it retains values after smaller requests.

## Validation and reproduction

- Both packaged versions pass all 20 daemon and four client tests. The new parser regression covers short records, missing header values and detached-header handling.
- The saved baseline suite passes 19 differential scenarios. Additional checks cover 30 PATH search/recovery streams, 27 protocol/client comparisons including 100 varied responses, and 150 randomized malformed/raw-byte status streams.
- Both versions pass PTY checks for asynchronous readiness, stale responses, duplicate-start rejection, lifetime and failure cleanup, and render the branch through actual Powerlevel10k.
- `zsh -n`, `rustfmt --check`, Nix worker/generated Quicksilver `.zshrc` builds and `./utils/flake-check.sh` pass.

Sources, binaries, compiler/package metadata, hashes, instrumentation, harnesses and raw samples are saved in:

`/var/folders/vk/46_34c_j3jldrt2kczqj3vfw0000gn/T/i4-git-status-opt-ctpkzyvh`

`micro.json` contains client CPU/peak RSS and Rust allocations; `parser-component.json` contains controlled worker CPU; `native-resources.json` contains checkout worker CPU/RSS; `daemon.json` contains full-request/startup timing; `long-memory.json` contains the long-lived RSS check. `path-inheritance/` preserves the rejected experiment and `parser-bench.json` records buffer-size comparisons.

Run from this checkout:

```bash
set -euo pipefail
artifact_dir=/var/folders/vk/46_34c_j3jldrt2kczqj3vfw0000gn/T/i4-git-status-opt-ctpkzyvh
python3 "$artifact_dir/micro.py"
python3 "$artifact_dir/parser-component.py"
python3 "$artifact_dir/native-resources.py"
PYTHONPATH="$PWD/tests" python3 "$artifact_dir/latency.py" \
  --baseline "$artifact_dir/before" --baseline-raw \
  --native "$artifact_dir/after" --samples 100 --startup-samples 10 \
  > "$artifact_dir/daemon.json"
python3 "$artifact_dir/long-memory.py"
```

Final worker: `/nix/store/bs1larvkqykx3jad2gx42aphs78hbaig-i4-git-status-daemon/git-status-daemon`.
