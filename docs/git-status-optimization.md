# Git status client and daemon optimization

Measured on 2026-10-01 on Apple M3 Max, macOS 26.7.1, Git 2.55.0 and Zsh 5.9.1. Baseline: `fe3a97ef9d585a4ddbfa7ca2ba07c4b56961cfb1`. Both final worker binaries are the actual Nix packages built with Rust 1.95.0, edition 2021, optimization level 3 and stripped symbols. Separate allocation probes use the same compiler and flags.

The client uses Zsh's `syswrite` for raw pipe writes and scopes `no_monitor` directly to the startup function. The send success/failure branch is shorter. [Zsh documents](https://zsh.sourceforge.io/Doc/Release/Zsh-Modules.html#index-syswrite) that `syswrite` completes short writes and retries interrupted writes. The worker reuses the consumed request-count buffer for status lines and groups the two fixed Git arguments.

Request bytes, PATH and Git overrides, Git arguments/order, twelve response fields, asynchronous redraws, stale responses, single-worker lifetime and failure cleanup are preserved.

| Source | Before | After |
| --- | ---: | ---: |
| Client | 126 lines | 121 lines |
| Worker | 214 lines | 213 lines |
| Total | 340 lines | 334 lines (-1.8%) |

## Client CPU and resident memory

Nine paired trials in randomized order, using compiled client files in fresh noninteractive Zsh processes. Each trial runs 10,000 sends or responses, or 3,000 sends with 100 extra exported Git variables. Sends write to `/dev/null`; responses read a prepared file with a stub redraw. CPU is user plus system time from `wait4`, divided by call count; shell startup is amortized across the loop. Peak shell RSS also comes from `wait4`.

| Workload | Before CPU (µs/call) | After CPU (µs/call) | Change | Before/after peak RSS (KiB) |
| --- | ---: | ---: | ---: | ---: |
| send | 74.30 | 67.79 | -8.8% | 3440 / 3472 |
| send-many | 277.66 | 267.34 | -3.7% | 3712 / 3744 |
| response | 43.94 | 43.87 | -0.2% | 3424 / 3472 |

Ordinary sends improve in all nine pairs; environment-heavy sends improve in eight. Response CPU is unchanged within noise. With `zsh/system` loaded, measured peak shell RSS rises by 32 KiB for sends and 48 KiB for responses. These are client microbenchmarks, separate from complete Git requests.

## Git request latency and worker RSS

Two persistent packaged workers, ten warmups, then 100 paired requests per case in randomized order. Every response is checked for byte equality. Ten RSS snapshots per worker are taken after requests with `ps`. Ten fresh processes per worker and case also measure startup. Latency includes pipes and Git subprocesses; RSS excludes Git subprocesses. Raw startup samples are in `daemon.json`.

| Repository | Before median/p95 (ms) | After median/p95 (ms) | Before/after worker RSS (KiB) |
| --- | ---: | ---: | ---: |
| non_repo | 11.40 / 14.26 | 11.44 / 14.99 | 2368 / 2656 |
| small_clean_10_files | 41.12 / 47.61 | 41.32 / 47.24 | 2584 / 2616 |
| checkout | 46.64 / 54.48 | 46.88 / 54.60 | 2424 / 2632 |
| large_clean_5000_files | 160.77 / 173.86 | 160.45 / 175.79 | 2616 / 2656 |
| large_dirty_5000_modified_200_untracked | 310.50 / 351.40 | 312.11 / 362.32 | 2432 / 2688 |

No consistent complete-request latency improvement was measured: median changes range from -0.2% to +0.5%. Resident memory did not decrease. Git launch and filesystem work dominate these requests.

## Fresh-process RSS comparisons

Ten additional worker pairs per workload, randomized request order, five requests before each RSS snapshot. All replies are compared for byte equality. Both workers are the final Nix packages.

| Environment | Before/after median RSS (KiB) | Before/after sample ranges (KiB) |
| --- | ---: | ---: |
| checkout | 2256 / 2280 | 2176-2304 / 2240-2336 |
| 100_git_variables | 2536 / 2632 | 2384-2656 / 2592-2688 |

The fresh-process medians rise by 24 KiB for the checkout and 96 KiB with 100 Git variables; ranges overlap. RSS includes code pages, allocator metadata and C allocations, so the Rust allocation savings below do not establish a resident-memory improvement.

## Rust allocation measurements

Instrumented workers count parent Rust allocator traffic over 100 checkout requests, including startup and shutdown, using an allocator that delegates to `System`. Peak live heap counts requested Rust allocation sizes and excludes allocator metadata, stacks, code pages, direct C allocations and Git subprocesses.

| Environment | Before/after allocations per request | Before/after allocated KiB per request | Before/after peak live heap (KiB) |
| --- | ---: | ---: | ---: |
| checkout | 501.98 / 500.00 | 107.36 / 107.17 | 74.49 / 74.62 |
| 100_git_variables | 3013.04 / 3011.06 | 405.84 / 405.65 | 113.06 / 113.05 |
| changed_path | 1427.98 / 1426.00 | 334.41 / 334.22 | 82.60 / 82.59 |

The worker saves 198 allocations and 19,206 allocated bytes over each 100-request run: about two allocations and 192 bytes per request. Ordinary checkout allocation count falls by 0.4%, allocated bytes by 0.2%. Its peak live Rust heap rises by 132 bytes; the other two cases fall by eight bytes. The reusable buffer retains capacity for the longest status line processed, so unusually long lines can leave more heap resident between requests.

## Reproduction and artifacts

Saved sources, packaged binaries, allocation instrumentation and its Nix builder, benchmark harnesses, metadata and raw samples are in:

`/var/folders/vk/46_34c_j3jldrt2kczqj3vfw0000gn/T/i4-git-status-opt-d6ynjvc1`

`metadata.json` records the baseline commit, source/binary hashes, line counts, compiler versions and package paths. `micro.json` contains client CPU/RSS and allocation measurements; `memory.json` contains fresh-process RSS; `daemon.json` contains latency, startup and RSS samples. `pairs-bench.json` and `syswrite-bench.json` are exploratory client comparisons.

```bash
set -euo pipefail
artifact_dir=/var/folders/vk/46_34c_j3jldrt2kczqj3vfw0000gn/T/i4-git-status-opt-d6ynjvc1
python3 "$artifact_dir/micro.py"
python3 tests/benchmark-git-status-daemon.py \
  --baseline "$artifact_dir/before" --baseline-raw \
  --native "$artifact_dir/after" --samples 100 --startup-samples 10
python3 "$artifact_dir/memory.py"
```

## Validation

- Packaged final worker: all 18 daemon tests pass, comparing repository responses with the saved baseline. Checks include Git command order, arguments and exact environment in C and UTF-8 locales.
- All four client tests pass on both versions, including a new 300,000-byte pipe-write test, byte/Unicode/NUL framing, worker lifetime, duplicate launches and failure cleanup.
- 27 extra differential checks pass, including a stream of 100 varied synthetic responses, truncation, invalid environment names/bytes, PATH changes/recovery, unusual exported parameter types and malformed responses.
- Paired PTY checks verify readiness before delayed Git completion, stale responses, duplicate sources and failure cleanup. Both versions render the branch through actual Powerlevel10k using the generated shell configuration.
- `zsh -n`, `rustfmt --check`, `./utils/flake-check.sh` and the generated Quicksilver `.zshrc`/worker build pass.

Final worker: `/nix/store/vfmk0qpbrkrn9g30lgr8wkpw0m653qdq-i4-git-status-daemon/git-status-daemon`.
