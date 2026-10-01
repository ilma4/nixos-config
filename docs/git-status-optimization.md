# Git status client and daemon optimization

Measured on 2026-10-01 on macOS-26.7.1-arm64-arm-64bit-Mach-O, git version 2.55.0 and zsh 5.9.1 (aarch64-apple-darwin25.6.0). Baseline: `29fedbfb824af5a0922e2ca07aba540a7028a916`. Complete request and worker CPU/RSS comparisons use the actual before/after Nix packages, built with Rust 1.95.0, edition 2021, optimization level 3 and stripped symbols. Allocation probes use the same compiler and flags.

The worker temporarily sets its own `GIT_OPTIONAL_LOCKS=0` while spawning the status child, then removes it before any auxiliary command. In this single-threaded process, a status child without other environment changes can inherit the environment directly, avoiding a full copy into Rust strings and an environment map. Request-specific lock values remain available to auxiliary commands, including invalid values that prevent those commands from spawning. The worker also borrows the upstream suffix instead of shifting its bytes, and simplifies optional PATH forwarding, reusable environment-buffer growth and error handling. The client returns early for cached responses, removing a nesting level.

Request bytes, exported Git variables, PATH, Git command arguments/order, twelve response fields, asynchronous redraws, stale responses, single-worker lifetime and failure cleanup are preserved.

| Source | Before | After |
| --- | ---: | ---: |
| Client | 121 lines | 120 lines |
| Worker | 213 lines | 208 lines |
| Total | 334 lines | 328 lines (-1.8%) |

## Client CPU and peak resident memory

Nine paired trials in randomized order, using compiled client files in fresh noninteractive Zsh processes. Each trial runs 10,000 sends or responses, or 3,000 sends with 100 extra exported Git variables. Sends write to `/dev/null`; responses read a prepared file and stub redraws. These loops spawn no worker or Git children. CPU is user plus system time from `wait4`, divided by calls; startup is amortized. Peak shell RSS also comes from `wait4`.

| Workload | Before CPU (µs/call) | After CPU (µs/call) | Change | Before/after peak RSS (KiB) |
| --- | ---: | ---: | ---: | ---: |
| send | 67.57 | 68.79 | +1.8% | 3488 / 3488 |
| send-many | 269.78 | 268.68 | -0.4% | 3760 / 3760 |
| response | 44.09 | 43.63 | -1.0% | 3456 / 3472 |

Client CPU and resident memory are essentially unchanged. No client speedup is established by these small differences.

## Worker CPU and resident memory

Seven fresh worker pairs per case, five warmups and 50 paired requests in randomized order. Every reply is checked for byte equality and all twelve fields. `proc_pid_rusage` queries only these launched worker PIDs, excluding Git children. CPU excludes startup and uses Mach time units converted with `mach_timebase_info`; a calibration against `getrusage(RUSAGE_SELF)` agreed within 0.02%. Each process has five RSS snapshots after every ten requests; the table gives the median of the seven process medians.

| Request environment | Before/after CPU (µs/request) | CPU change | Before/after RSS (KiB) | Before/after RSS ranges (KiB) |
| --- | ---: | ---: | ---: | ---: |
| No Git overrides, inherited PATH | 7444.61 / 7344.65 | -1.3% | 2624 / 1904 | 2480-2672 / 1872-1984 |
| One Git variable (GIT_PAGER) | 7532.76 / 7575.04 | +0.6% | 2592 / 2576 | 2560-2688 / 2544-2624 |
| 100 Git variables | 7721.39 / 7623.73 | -1.3% | 2656 / 2656 | 2592-2736 / 2608-2672 |
| Changed PATH | 1310.59 / 1309.72 | -0.1% | 2560 / 2592 | 2496-2640 / 2544-2624 |

With no Git overrides and an unchanged PATH, worker RSS falls by 720 KiB (27.4%); the sampled ranges do not overlap. Other cases are unchanged within their overlapping ranges because their overrides still require a full environment copy. No reliable worker CPU improvement was measured.

A separate 1,000-request non-repository run checks longer worker lifetimes. Before RSS at requests 5/100/500/1000 was 2256 / 2592 / 2592 / 2592 KiB; after RSS was 1888 / 1968 / 1984 / 1984 KiB. Both are stable between requests 500 and 1000.

`ps` was unavailable in the sandbox, so worker RSS uses the direct API. A control experiment showed that macOS `wait4` includes waited Git child CPU and peak RSS; it is therefore unsuitable for isolating this worker. Client-only `wait4` measurements above do not have that issue.

## Rust allocations and peak live heap

Instrumented workers count parent Rust allocator traffic over 100 checkout requests, including startup and shutdown, with an allocator delegating to `System`. Peak live heap counts requested Rust allocation sizes; it excludes allocator metadata, stacks, code pages, direct C allocations and Git children.

| Request environment | Before/after allocations per request | Before/after allocated KiB per request | Before/after peak live heap (KiB) |
| --- | ---: | ---: | ---: |
| No Git overrides, inherited PATH | 510.06 / 38.06 | 108.31 / 5.44 | 75.76 / 44.78 |
| 100 Git variables | 3042.12 / 3040.12 | 409.60 / 409.58 | 114.25 / 114.25 |
| Changed PATH | 1456.06 / 1454.06 | 338.48 / 338.46 | 83.88 / 83.88 |

Without overrides, allocation count falls by 92.5%, allocated bytes by 95.0%, and peak live Rust heap by 40.9%. Cases with Git variables or changed PATH save only two allocations and 19 allocated bytes per request, with unchanged peak live heap.

## Complete Git request latency

Two persistent packaged workers, ten warmups, then 100 paired requests per repository in randomized order, plus ten fresh-process startup samples per version and repository. Every reply is checked for byte equality. Latency includes pipes and all Git subprocesses. Git repository fixtures disable fsmonitor and the untracked cache. Startup samples remain in the raw report.

| Repository | Before median/p95 (ms) | After median/p95 (ms) | Median change |
| --- | ---: | ---: | ---: |
| non_repo | 10.17 / 12.21 | 10.33 / 13.82 | +1.6% |
| small_clean_10_files | 38.83 / 45.63 | 39.46 / 44.48 | +1.6% |
| checkout | 46.72 / 52.98 | 46.96 / 52.18 | +0.5% |
| large_clean_5000_files | 48.34 / 52.41 | 48.24 / 54.00 | -0.2% |
| large_dirty_5000_modified_200_untracked | 274.27 / 302.22 | 271.78 / 301.97 | -0.9% |

No consistent complete-request speedup was measured. Median changes range from -0.9% to +1.7%; Git launch and filesystem work dominate. The measured improvement is lower memory consumption for requests without overrides.

## Reproduction and artifacts

Saved sources, packaged binaries, allocation instrumentation, harnesses, metadata and raw samples are in:

`/var/folders/vk/46_34c_j3jldrt2kczqj3vfw0000gn/T/i4-git-status-opt-cbf0yzry`

`metadata.json` records the baseline revision, source/binary hashes, line counts and package paths. `micro.json` contains client CPU/RSS and Rust allocations; `native-resources.json` contains actual packaged-worker CPU and RSS samples; `daemon.json` contains complete-request latency and startup samples; `long-memory.json` contains the longer-lifetime RSS check. `resources.json` contains exploratory probes linked with the system linker and is not used for the reported packaged-worker results.

Run from this checkout:

```bash
set -euo pipefail
artifact_dir=/var/folders/vk/46_34c_j3jldrt2kczqj3vfw0000gn/T/i4-git-status-opt-cbf0yzry
python3 "$artifact_dir/micro.py"
PYTHONPATH="$PWD/tests" python3 "$artifact_dir/latency.py" \
  --baseline "$artifact_dir/before" --baseline-raw \
  --native "$artifact_dir/after" --samples 100 --startup-samples 10 \
  > "$artifact_dir/daemon.json"
python3 "$artifact_dir/native-resources.py"
python3 "$artifact_dir/long-memory.py"
```

## Validation

- All 19 daemon and four client tests pass on both versions. Checks include Git command order/arguments, exact environments with absent and explicit overrides, NUL lock values, PATH failure/recovery, reftable/worktrees, byte/Unicode framing, complete 300,000-byte writes, worker lifetime and failure cleanup.
- The client lifecycle test now requires a fresh daemon reply after every directory change and foreground command, including an unchanged directory; it checks responsiveness directly instead of inspecting a cached prompt or process-state string.
- The saved baseline differential suite passes all 18 daemon scenarios. Another 27 differential checks pass, including 100 varied synthetic replies, truncation, invalid names/bytes, unusual exported parameter types and malformed responses.
- Paired PTY checks confirm an initial prompt before delayed Git completion, stale-response handling, duplicate-source rejection and failure cleanup. Both versions render the branch through actual Powerlevel10k using the generated shell configuration.
- `zsh -n`, `rustfmt --check`, the final `./utils/flake-check.sh` and Nix worker/generated Quicksilver `.zshrc` builds pass.

Final worker: `/nix/store/yl2wqbrnlv1xrg51l0363rkbxv0avi0r-i4-git-status-daemon/git-status-daemon`.
