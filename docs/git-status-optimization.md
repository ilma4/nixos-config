# Git status client and daemon optimization

Measured on 2026-10-01 on Apple M3 Max, macOS 26.7.1, Git 2.55.0 and Zsh 5.9.1. Baseline: `18068852064c0db6176040393d25d7a450831c8a`. The worker measurements use Nix-packaged binaries built with Rust 1.95.0, edition 2021, optimization level 3 and stripped symbols. Allocation probes use the same Nix compiler and compiler-enabled builder. Local Rust 1.98.1 exploratory builds are retained separately in the artifacts and are not the final worker measurements.

The client serializes environment values directly and groups directory-reset assignments. The worker reuses one path for action-marker checks, borrows status lines without their final newline, and simplifies trailing-newline removal and numeric parsing. Action detection retains the original `is_dir` and `exists` checks and precedence.

Baseline comparisons preserve request framing, per-request PATH and Git variables, Git command arguments and order, all twelve response fields, asynchronous redraws, stale-response handling, single-worker lifetime and failure cleanup. This pass changes no Nix options or packages.

| Source | Before | After |
| --- | ---: | ---: |
| Client | 128 lines | 126 lines |
| Worker | 217 lines | 214 lines |
| Total | 345 lines | 340 lines (-1.4%) |

## Client CPU and resident memory

Nine paired trials in randomized order, using compiled client files in fresh noninteractive Zsh processes. Each trial runs 10,000 sends or responses, or 3,000 sends with 100 additional exported Git variables. Sends write to `/dev/null`; responses read a prepared file and use a stub redraw function. CPU is user plus system time from `wait4`, divided by call count; shell startup is amortized across the loop. Peak shell RSS comes from `wait4`.

| Workload | Before CPU (µs/call) | After CPU (µs/call) | Change | Before/after peak RSS (KiB) |
| --- | ---: | ---: | ---: | ---: |
| send | 77.35 | 78.49 | +1.5% | 3456 / 3488 |
| send-many | 292.05 | 286.20 | -2.0% | 3728 / 3760 |
| response | 45.58 | 45.78 | +0.4% | 3424 / 3440 |

Sending with 100 additional Git variables uses 2.0% less CPU by median and improves in eight of nine paired trials. Ordinary sends and responses show no reliable improvement. No shell peak-RSS reduction was measured.

## Git request latency and worker RSS

Two persistent Nix-built workers, ten warmups, then 100 paired requests per repository in randomized order. Every response is checked for byte equality. Ten RSS samples per worker are taken after responses with `ps`. Latency includes pipes and Git subprocesses; RSS excludes Git subprocesses. Ten fresh processes per worker and case also measure startup; raw startup samples are retained in `daemon.json`.

| Repository | Before median/p95 (ms) | After median/p95 (ms) | Before/after worker RSS (KiB) |
| --- | ---: | ---: | ---: |
| non_repo | 11.67 / 13.76 | 11.90 / 14.31 | 2624 / 2592 |
| small_clean_10_files | 41.74 / 47.33 | 42.43 / 47.12 | 2656 / 2632 |
| checkout | 48.43 / 54.44 | 48.61 / 54.80 | 2752 / 2496 |
| large_clean_5000_files | 51.04 / 55.98 | 51.26 / 55.18 | 2640 / 2592 |
| large_dirty_5000_modified_200_untracked | 260.07 / 273.74 | 260.47 / 279.47 | 2656 / 2456 |

These trials do not establish a consistent overall Git-request latency improvement. Git process launch and filesystem work dominate the small amount of worker work removed.

## Fresh-process RSS comparisons

Ten additional worker pairs per workload, with randomized request order and five requests before each RSS snapshot. All replies are compared for byte equality. These use the same Nix-packaged workers as the latency benchmark.

| Environment | Before/after median RSS (KiB) | Before/after sample ranges (KiB) |
| --- | ---: | ---: |
| checkout | 2288 / 2280 | 2272-2320 / 2160-2320 |
| 100_git_variables | 2664 / 2536 | 2624-2672 / 2384-2656 |

RSS depends on workload and process layout. The ordinary checkout medians are almost identical; the environment-heavy workload has a lower median after the change, with overlapping ranges. Local exploratory builds produced different RSS results, so the allocation savings should not be treated as a general reduction in resident memory.

## Rust allocation measurements

Separate Nix-built instrumented workers count parent Rust allocator traffic over 100 checkout requests, including startup and shutdown. The allocator delegates to `System`. Peak live heap counts requested Rust allocation sizes, excluding allocator metadata, stacks, code pages, direct C allocations and Git subprocesses. It is distinct from RSS.

| Environment | Before/after allocations per request | Before/after allocated KiB per request | Before/after peak live heap (KiB) |
| --- | ---: | ---: | ---: |
| checkout | 514.98 / 502.98 | 108.30 / 107.63 | 74.49 / 74.49 |
| 100_git_variables | 3026.04 / 3014.04 | 406.78 / 406.11 | 113.20 / 113.20 |
| changed_path | 1440.98 / 1428.98 | 335.35 / 334.68 | 82.74 / 82.74 |

For these checkout responses, path reuse saves 12 allocations and 684 allocated bytes per request. Ordinary checkout allocation count falls by 2.3%, and allocated bytes by 0.6%. The saving depends on Git-directory length and how many action markers need checking. Peak live Rust heap is unchanged in all three workloads.

## Reproduction and artifacts

Saved sources, Nix-built binaries, allocator instrumentation and its Nix builder, benchmark harnesses and raw samples are in:

`/var/folders/vk/46_34c_j3jldrt2kczqj3vfw0000gn/T/i4-git-status-opt-wydqlw1v`

`metadata.json` records the baseline commit, source hashes and line counts, binary hashes, package paths and compiler versions. `micro.json` contains client CPU/RSS and final allocation measurements; `memory.json` contains fresh-process RSS samples. `daemon.json` contains final latency, startup and RSS samples. Files prefixed with `experimental-` and the candidate files contain exploratory results rather than final comparisons.

From the repository, repeat the measurements with the saved binaries:

```bash
set -euo pipefail
artifact_dir=/var/folders/vk/46_34c_j3jldrt2kczqj3vfw0000gn/T/i4-git-status-opt-wydqlw1v
python3 "$artifact_dir/micro.py"
python3 tests/benchmark-git-status-daemon.py \
  --baseline "$artifact_dir/before" --baseline-raw \
  --native "$artifact_dir/after" --samples 100 --startup-samples 10
python3 "$artifact_dir/memory.py"
```

The benchmark now accepts `--baseline-raw` for a current byte-length-prefixed baseline, while retaining the older quoted-baseline mode.

## Validation

- Baseline and final packaged worker: all 18 daemon tests and three client tests pass.
- All daemon repository cases compare stdout and stderr against the saved baseline package. Git command order, arguments and exact forwarded environment are checked in C and UTF-8 locales.
- 27 additional differential checks cover framing, truncation, invalid environment names/bytes, PATH changes and recovery, plus a stream of 100 varied synthetic responses. Client checks cover exported variable types, local shadowing, arbitrary bytes, Unicode, NUL and malformed/empty/long responses.
- Paired PTY checks cover asynchronous readiness before delayed Git completion, stale responses, duplicate launches and failure cleanup. Both packaged versions render the branch through actual Powerlevel10k using the generated shell configuration.
- `zsh -n`, `rustfmt --check`, `./utils/flake-check.sh` and the generated Quicksilver `.zshrc` build pass.

Final validated worker: `/nix/store/3kyw3a95zh1r2x5326nkixv1kyl6lbk5-i4-git-status-daemon/git-status-daemon`.
