# Jujutsu prompt integration measurements

Measured 2026-11-13 on Apple M3 Max / macOS. Git 2.56.0, JJ 0.46.0. The paired Git workers use the same Rust 1.99.1 compiler, edition 2021, optimization level 3 and stripped symbols. These measurements describe asynchronous status availability, not typing latency or shell startup.

## Git regression comparison

Two persistent workers, ten warmups and 100 randomized paired requests per fixture; ten fresh-process first-response measurements per worker. Every Git reply is checked byte-for-byte. Synthetic repositories disable fsmonitor and untracked caches. The dirty fixture modifies 5,000 files, stages 1,000, and adds 200 untracked files. The deep case adds 20 subdirectory levels.

| Case | Before median / p95 (ms) | After median / p95 (ms) | Median change |
| --- | ---: | ---: | ---: |
| non_repo | 10.71 / 13.36 | 10.67 / 13.00 | -0.3% |
| small_clean_10_files | 40.87 / 45.09 | 40.19 / 45.03 | -1.7% |
| large_clean_5000_files | 293.60 / 332.38 | 294.55 / 332.85 | +0.3% |
| large_dirty_5000_modified_200_untracked | 339.45 / 370.19 | 341.01 / 392.75 | +0.5% |
| small_deep_git | 44.48 / 48.68 | 44.43 / 49.90 | -0.1% |

All cases meet the planned median limit (5% or 1 ms, whichever is larger) and p95 limit (10% or 2 ms). No consistent Git slowdown is established. Absolute timings varied during the build/download workload; paired comparisons are more useful than comparison with the exploratory baseline. Ordinary Git requests add filesystem checks and launch no JJ processes.

## JJ refresh latency

Each fixture uses ten warmups and 100 measured requests. Refreshes snapshot the working copy and select the closest bookmark. Dirty warm measurements include unchanged refreshes of a nonempty current commit. The first dirty refresh separately measures snapshotting newly modified files; it is a single observation, not a distribution.

| Case | Warm median / p95 (ms) | First refresh (ms) |
| --- | ---: | ---: |
| 10_files_clean | 104.84 / 110.61 | 363.36 |
| 10_files_dirty | 104.38 / 112.07 | 153.05 |
| 5000_files_clean | 109.51 / 117.32 | 113.39 |
| 5000_files_dirty | 119.89 / 124.95 | 286.94 |

JJ uses the existing asynchronous client and daemon. Changes are counted against the merged parent tree; inherited unresolved conflicts are also reported. Renames/copies reported by JJ count as modified files. The closest local bookmark is selected by minimum parent-edge distance with alphabetical ties. Names use JSON escaping for safe line framing and prompt percent signs are escaped during rendering. No bookmark means an eight-character change ID.

## Validation and reproduction

The packaged Rust 1.95.0 worker and compiled Zsh client pass the Git daemon, JJ daemon, and interactive client suites. The interactive suite includes actual Powerlevel10k rendering when I4_TEST_P10K_THEME points to the theme. The generated Quicksilver .zshrc builds, syntax/format checks pass, and ./utils/flake-check.sh passes. Configuration was not activated.

Raw Git samples, startup measurements and worker RSS, JJ samples, and before/after binaries are saved in /tmp/jj-prompt-baseline. RSS excludes subprocesses. Reproduce against a saved original worker; omit the colocated checkout from byte-identical Git comparisons because it now intentionally uses JJ:

```bash
set -euo pipefail
jj file show -r 19193785 home/git-status-daemon.rs > /tmp/jj-prompt-before.rs
rustc --edition=2021 -C opt-level=3 -C strip=symbols /tmp/jj-prompt-before.rs -o /tmp/jj-prompt-before
python3 tests/benchmark-git-status-daemon.py --baseline /tmp/jj-prompt-before --baseline-raw \
  --samples 100 --startup-samples 10 --case non_repo --case small_clean_10_files \
  --case small_deep_git --case large_clean_5000_files \
  --case large_dirty_5000_modified_200_untracked > /tmp/jj-prompt-git.json
python3 tests/benchmark-jj-status-daemon.py > /tmp/jj-prompt-jj.json
```

## Upstream divergence indicators

The JJ segment also shows `⇡N` and `⇣N` for commits in `@` versus the closest
local bookmark's tracked remote target. This includes the working-copy commit,
even when empty, and commits between that bookmark and `@`. Zero counts are hidden.
Prefer `origin` when tracked; otherwise use the sole distinct tracked target.
If no target exists or multiple other targets disagree, omit the arrows.
These commands run only for JJ requests; the Git request path is unchanged.

The packaged worker/client pass 36 tests, including synchronized, ahead-only,
behind-only, diverged, untracked, and arrow-rendering cases. The generated Zsh
configuration builds and the final flake check passes. No activation was run.

The JJ timings above were refreshed after this addition with no tracked remote.
For the tracked-remote workload, run:

```bash
set -euo pipefail
python3 tests/benchmark-jj-status-daemon.py --tracked-remote --samples 100
```

Tracked-remote measurements (30 requests per case, ten warmups):

| Case | Median / p95 (ms) |
| --- | ---: |
| 10_files_clean | 139.77 / 150.37 |
| 10_files_dirty | 142.82 / 149.51 |
| 5000_files_clean | 150.04 / 159.08 |
| 5000_files_dirty | 156.12 / 164.71 |

Raw samples: `/tmp/jj-ahead-benchmark.json` and `/tmp/jj-ahead-tracked-benchmark.json`.
