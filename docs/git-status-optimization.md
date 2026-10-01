# Git status client and daemon optimization

Measured on 2026-10-01 on Apple M3 Max, macOS 26.7.1, Git 2.55.0, Zsh 5.9.1 and rustc 1.98.1. Baseline: `48eebf379c2a4dabb48b9c6d903f96456e721bab`. Both worker binaries use edition 2021, optimization level 3 and stripped symbols.

The client groups VCS string and integer assignments into two `typeset` calls. Readiness is updated after those assignments. The worker builds complete responses in one reusable byte buffer and writes each response to locked stdout. Action lookup uses `find_map` to combine lookup and conversion.

The request format, Git commands and their environment, response fields, prompt rendering and daemon lifecycle are preserved. This pass changes no Nix options or packages.

| Source | Before | After |
| --- | ---: | ---: |
| Client | 130 lines | 128 lines |
| Worker | 218 lines | 217 lines |
| Total | 348 lines | 345 lines (-0.9%) |

## Client CPU and resident memory

Nine paired trials in randomized order, using compiled client files in fresh noninteractive Zsh processes. Each trial runs 10,000 sends or responses, or 3,000 sends with 100 extra exported Git variables. Sends write to `/dev/null`; responses read a prepared file and use a stub redraw function. CPU is user plus system time from `wait4`, divided by call count; shell startup is amortized across the loop. Peak shell RSS is also measured with `wait4`.

| Workload | Before CPU (µs/call) | After CPU (µs/call) | Change | Before/after peak RSS (KiB) |
| --- | ---: | ---: | ---: | ---: |
| send | 75.98 | 77.14 | +1.5% | 3472 / 3456 |
| send-many | 289.60 | 289.83 | +0.1% | 3760 / 3744 |
| response | 50.68 | 44.91 | -11.4% | 3440 / 3408 |

Response handling uses 11.4% less CPU. Request serialization is unchanged; the measured send differences are small compared with trial variation. Shell peak RSS shows no meaningful improvement.

## Git request latency and worker RSS

Two persistent workers, ten warmups, then 100 paired requests per repository in randomized order. Every response is checked for byte equality. Ten RSS samples per worker are taken after responses with `ps`; Git subprocess memory is excluded. Latency includes pipes and Git subprocesses, using prepared request bytes. Ten fresh processes per worker and case also measure startup; raw startup samples are retained in `daemon.json`.

| Repository | Before median/p95 (ms) | After median/p95 (ms) | Before/after worker RSS (KiB) |
| --- | ---: | ---: | ---: |
| non_repo | 11.65 / 13.84 | 11.47 / 14.77 | 2640 / 2640 |
| small_clean_10_files | 44.34 / 49.44 | 43.92 / 49.08 | 2608 / 2672 |
| checkout | 50.75 / 56.01 | 50.51 / 56.62 | 2624 / 2632 |
| large_clean_5000_files | 52.46 / 57.21 | 52.19 / 58.36 | 2624 / 2640 |
| large_dirty_5000_modified_200_untracked | 309.86 / 340.63 | 310.99 / 342.47 | 2656 / 2640 |

No clear overall Git latency or worker RSS improvement was measured. Checkout latency changes by -0.5%; the dirty repository changes by +0.4%. RSS varies in both directions. These measurements do not establish an end-to-end prompt speedup.

## Rust allocation measurements

Separate instrumented builds count parent Rust allocator traffic over 100 checkout requests, including startup and shutdown. The instrumented allocator delegates allocation, reallocation and deallocation to `System`. Peak live heap counts requested Rust allocation sizes, excluding allocator metadata, stacks, code pages and Git subprocesses. It is distinct from RSS.

| Environment | Before/after allocations per request | Before/after allocated KiB per request | Before/after peak live heap (KiB) |
| --- | ---: | ---: | ---: |
| checkout | 514.98 / 513.98 | 108.11 / 108.02 | 74.49 / 74.49 |
| 100_git_variables | 3026.04 / 3025.04 | 406.59 / 406.50 | 113.06 / 113.06 |
| changed_path | 1440.98 / 1439.98 | 335.16 / 335.08 | 82.60 / 82.60 |

For these repository responses the worker saves one allocation and 88 allocated bytes per request. Normal allocation traffic falls by only 0.08%. Peak live heap is unchanged in all three workloads. The main measured improvement is client response CPU, with a small reduction in worker allocation traffic.

## Reproduction and artifacts

Saved before/after sources, compiled binaries, allocator instrumentation, benchmark harnesses and raw samples are in:

`/var/folders/vk/46_34c_j3jldrt2kczqj3vfw0000gn/T/i4-git-status-final.puzltlgj`

`metadata.json` records source hashes, source line counts and tool versions. `micro.json` contains the final client and heap results; `client-final.json` retains the client trials separately. `daemon.json` contains latency, startup and RSS samples. The saved daemon benchmark accepts raw requests for both workers; the repository benchmark's existing `--baseline` flag expects the older quoted request format.

To repeat the measurements from the artifact directory:

```bash
set -euo pipefail
python3 micro.py
python3 benchmark-daemon.py --baseline ./before --native ./after \
  --samples 100 --startup-samples 10 > daemon.json
```

## Validation

- Baseline: all 18 daemon tests and three client tests passed.
- Updated worker: 18 daemon tests passed, with repository cases compared against the saved baseline.
- Additional differential checks compare framing, truncation, invalid environment entries, PATH changes and both C/UTF-8 locales. A stream of 100 varied synthetic responses checks long fields and IDs, embedded control bytes, status failures, action precedence and buffer reuse.
- Client comparisons cover exported variable types, local shadowing, arbitrary bytes, Unicode, NUL and malformed/empty/long responses. Both versions produce identical request bytes and VCS variable assignments.
- Paired PTY checks cover asynchronous readiness before delayed Git completion, stale responses, duplicate launches and failure cleanup. Both versions render the branch through actual Powerlevel10k.
- `zsh -n`, `rustfmt --check`, `./utils/flake-check.sh` and the generated Quicksilver `.zshrc` build pass. The Nix-built worker and compiled client pass all 21 tests and render the branch through the generated Powerlevel10k configuration.

Validated Nix package: `/nix/store/lh7m1nm7rqg3vfiss8w9n4ky1kk0dqdi-i4-git-status-daemon`.
