# Git status client and daemon optimization

Measured on 2026-10-01 on Apple M3 Max, macOS 26.7.1, Git 2.55.0, Zsh 5.9.1. Both Rust binaries used rustc 1.98.1, edition 2021, optimization level 3 and stripped symbols. Baseline: `1d51774468733f901791e7f0214fe9357d0abe96`.

The client now sends raw fields with a decimal byte length and newline before each field. The worker reads exactly that many bytes. This removes Zsh quoting and the Rust unquoting decoder. Byte lengths are calculated with `no_multibyte` scoped to the send function, and the previous option state is restored. Empty values, newlines, arbitrary non-UTF-8 bytes and embedded NUL remain framed correctly. Git still rejects NUL-containing arguments or environment entries; the following request remains usable.

The client and worker ship together in the same Nix derivation. The internal request format changes; both files must be updated together. Git commands, their order and environment, response fields, prompt rendering and lifecycle handling remain unchanged.

| Source | Before | After |
| --- | ---: | ---: |
| Client | 134 lines | 132 lines |
| Worker | 263 lines | 220 lines |
| Total | 397 lines | 352 lines (-11.3%) |

## Client CPU and memory

Nine paired trials in randomized order, using compiled client files in fresh `zsh -f` processes. Each trial runs 10,000 sends or responses, or 3,000 sends with extra variables. CPU is user plus system time from `wait4`, divided by the call count; startup is amortized across the loop. Send workloads export two Git variables, including quotes/newlines; the larger workload adds 100 more. Inherited PATH is 4,025 bytes. Response handling uses identical response fields.

| Workload | Before CPU (µs/call) | After CPU (µs/call) | Reduction | Before/after peak shell RSS (KiB) |
| --- | ---: | ---: | ---: | ---: |
| send | 169.45 | 125.41 | 26.0% | 3584 / 3536 |
| send-many | 541.42 | 503.50 | 7.0% | 3888 / 3824 |
| response | 78.23 | 77.71 | 0.7% | 3584 / 3536 |

Request serialization improves; response processing and shell peak RSS are effectively unchanged.

## Git request latency and resident worker memory

Two persistent workers, ten warmups, then 100 paired requests per case in randomized order. Every response is checked for byte equality. Ten RSS samples per worker are taken after responses with `ps`; Git subprocess memory is excluded. These timings include pipe IPC and Git subprocesses, with prebuilt requests. Ten fresh processes per worker and case also measured startup; their raw samples are retained.

| Repository | Before median/p95 (ms) | After median/p95 (ms) | Before/after worker RSS (KiB) |
| --- | ---: | ---: | ---: |
| non_repo | 18.41 / 40.33 | 18.63 / 40.40 | 2704 / 2472 |
| small_clean_10_files | 80.21 / 143.56 | 86.59 / 133.24 | 2336 / 2320 |
| checkout | 77.97 / 93.06 | 78.08 / 98.93 | 2752 / 2592 |
| large_clean_5000_files | 124.85 / 201.00 | 125.92 / 232.29 | 2632 / 2448 |
| large_dirty_5000_modified_200_untracked | 442.74 / 518.91 | 441.40 / 504.09 | 2760 / 2728 |

Git request latency shows no clear overall improvement. The 10-file case is 8.0% slower by median in this run, while the dirty case is 0.3% faster; tail latency varies considerably. The checkout changes from 77.97 to 78.08 ms (+0.14%). Resident memory readings are slightly lower, but a single worker pair per workload cannot establish a reliable RSS reduction.

## Rust allocation measurements

Instrumented builds count parent Rust allocator traffic over 100 checkout requests, including startup and shutdown. These runs are separate from latency measurements. Peak live heap counts requested Rust allocation sizes, excluding allocator metadata, stacks, code pages and Git subprocesses. It is distinct from RSS.

| Environment | Before/after allocations per request | Before/after allocated KiB per request | Before/after peak live heap (KiB) |
| --- | ---: | ---: | ---: |
| checkout | 520.41 / 519.93 | 117.25 / 116.36 | 74.31 / 74.32 |
| 100_git_variables | 3234.07 / 3232.93 | 433.68 / 431.05 | 117.74 / 116.54 |
| changed_path | 1446.40 / 1445.93 | 343.84 / 343.43 | 90.49 / 90.49 |

Allocation traffic falls by less than 1%. Normal peak heap is unchanged (76,094 → 76,101 bytes); with 100 extra Git variables it falls 1.0% (120,567 → 119,333 bytes). The meaningful measured gain is client CPU, with a smaller worker implementation.

## Reproduction and artifacts

```bash
set -euo pipefail
jj file show -r 1d517744 home/git-status-daemon.rs > /tmp/git-status-before.rs
rustc --edition=2021 -C opt-level=3 -C strip=symbols /tmp/git-status-before.rs -o /tmp/git-status-before
python3 tests/benchmark-git-status-daemon.py \
  --baseline /tmp/git-status-before --samples 100 --startup-samples 10 \
  > /tmp/git-status-comparison.json
```

Full raw samples, saved before/after sources, binaries, allocation instrumentation, client benchmark harness and differential/PTY checks are stored in:

`/var/folders/vk/46_34c_j3jldrt2kczqj3vfw0000gn/T/i4-git-status-next.o30_7mcb`

Run `python3 <artifact-directory>/micro.py` to repeat client CPU/RSS and worker heap measurements using the saved sources. `daemon.json` contains Git latency and worker RSS samples; `micro.json` contains CPU, peak shell RSS and allocator samples; `metadata.json` records tool versions and source hashes.

## Validation

Baseline: 17 daemon tests and two PTY lifecycle tests passed. Updated worker: 18 daemon tests passed, including the original repository/environment cases compared with the saved Rust baseline and a new NUL/recovery case. Three client tests cover lifecycle plus byte framing and multibyte option restoration. Additional differential checks cover empty/malformed responses, all non-NUL byte values, Unicode, embedded NUL, unexported variables, PATH changes and both C/UTF-8 locales.

Paired PTY checks confirm an initial prompt before deliberately delayed Git completion, stale-response handling, duplicate-launch rejection and failure cleanup. Both clients render the branch through actual Powerlevel10k. `zsh -n` and `rustfmt --check` pass. `./utils/flake-check.sh` passes for all systems. The Quicksilver worker and generated `.zshrc` build successfully; the packaged arm64 worker and compiled client pass all 21 tests and render the branch through the generated Powerlevel10k configuration. Configuration was not activated.

Validated Nix worker package: `/nix/store/34ib6dxmcl4nvvqw37h0c5sqbbf90is0-i4-git-status-daemon`.
