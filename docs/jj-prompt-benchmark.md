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

## Refresh query optimization

The optimized worker combines working-copy metadata and the first 16-generation
ancestry window in one snapshotting query. A second query returns upstream target
markers and ahead/behind counts together. A typical tracked-bookmark refresh now
starts two JJ processes instead of four. Deeper bookmark searches still expand
the ancestry window as needed. With no upstream, the divergence query compares
`@` to itself, avoiding a traversal of the entire history.

Measured 2026-11-13 with before/after workers compiled using the same Rust compiler
and optimization flags. Synthetic tracked-remote fixtures use ten warmups and 40
samples per case; before and after are separate runs, so their comparison also
includes run-to-run variation. These timings measure asynchronous status refresh,
not shell startup or typing latency.

| Tracked-remote case | Before median / p95 (ms) | After median / p95 (ms) |
| --- | ---: | ---: |
| 10 files, clean | 143.24 / 147.90 | 72.56 / 80.44 |
| 10 files, dirty | 139.06 / 146.16 | 75.42 / 81.12 |
| 5000 files, clean | 151.82 / 176.13 | 83.08 / 88.87 |
| 5000 files, dirty | 146.19 / 154.22 | 88.37 / 97.60 |

In this checkout, 50 randomized paired requests returned identical status bytes.
With matched compilers, median refresh time fell from **167.01 to 85.66 ms**
(48.7%); p95 fell from 192.90 to 105.76 ms. Ten warmups and five first-response
samples per worker were also collected.

Thirty randomized paired requests for each ordinary Git fixture returned identical
bytes before and after. Median times were 14.16 to 14.45 ms outside a repository,
42.86 to 43.40 ms for ten clean files, and 264.60 to 262.80 ms for 5000 modified
files plus 200 untracked files. The Git implementation is unchanged.

All 38 integration tests pass against the Nix-built worker and compiled client,
including actual Powerlevel10k rendering, escaped bookmark names, shared and
ambiguous remote targets, origin preference, snapshotting edits, merges, and deep
bookmark lookup. The generated Quicksilver `.zshrc` builds and passes syntax
checking, and `./utils/flake-check.sh` passes. No configuration activation was run.

Raw measurements and matched-compiler binaries are in
`/tmp/jj-prompt-optimization`. To reproduce the paired checkout comparison with
saved before/after binaries:

```bash
set -euo pipefail
GIT_STATUS_DAEMON=/tmp/jj-prompt-optimization/after \
  python3 tests/benchmark-git-status-daemon.py \
  --baseline /tmp/jj-prompt-optimization/before --baseline-raw \
  --samples 50 --startup-samples 5 --case checkout
```

## One-process warm refreshes

The worker now remembers the previous closest bookmark's escaped name as a query
hint. It includes that bookmark's upstream comparison in the next snapshotting
query, then verifies the name using the fresh ancestry graph. When the name still
matches, metadata, file counts, conflicts and divergence all come from one JJ
process. No status results are cached. A cold refresh or a changed closest
bookmark still uses two queries; deep ancestry searches can require more.

Measured 2026-11-13 in this checkout using matched compiler/optimization flags,
ten warmups and 50 randomized paired requests. Every reply was byte-identical.
These timings measure asynchronous status availability, not typing latency.

| Case | Before median / p95 (ms) | After median / p95 (ms) |
| --- | ---: | ---: |
| Checkout, tracked bookmark | 100.46 / 119.82 | 52.65 / 63.65 |

Median refresh time improved by **47.6%**. First-response timings (five per worker)
and raw samples are included in `/tmp/jj-prompt-next/checkout.json`. Ordinary Git
requests are unchanged; 25 randomized paired requests per non-repository, small
clean Git, and large dirty Git fixture also returned identical bytes.

All 39 integration tests pass against the Nix-built worker and compiled client,
including actual Powerlevel10k rendering. JJ tests now keep workers alive across
refreshes, exercising snapshotting edits, remote target changes, bookmark changes,
escaped names, merges, deep ancestry and repository changes. A counting wrapper
checks that warm refreshes launch one JJ process and changed bookmarks trigger
the fallback. An additional 19 status comparisons across nine JJ tests matched
the previous worker. The generated Quicksilver `.zshrc` builds and passes syntax
checking; `./utils/flake-check.sh` passes. Configuration was not activated.

Matched-compiler binaries and raw measurements are in `/tmp/jj-prompt-next`:

```bash
set -euo pipefail
GIT_STATUS_DAEMON=/tmp/jj-prompt-next/after \
  python3 tests/benchmark-git-status-daemon.py \
  --baseline /tmp/jj-prompt-next/before --baseline-raw \
  --samples 50 --startup-samples 5 --case checkout
```

## Adaptive ancestry windows

The worker now remembers the successful ancestry window alongside the bookmark
name. Previously, a bookmark beyond the first 16 generations required repeated
window expansion on every refresh, even when its name was already known. Warm
refreshes now start with enough generations to find that bookmark in one query.
The window rounds up to a power of two, with a minimum of 16, and shrinks after
finding a closer bookmark. Names, file status and upstream counts are still
recomputed and verified on every request.

Measured 2026-11-13 using matched compiler/optimization flags, ten warmups and 40
randomized paired requests per case. Synthetic fixtures contain ten files and a
tracked remote bookmark. Every paired reply was byte-identical.

| Bookmark distance | Before median / p95 (ms) | After median / p95 (ms) |
| --- | ---: | ---: |
| 1 commit | 39.91 / 42.83 | 38.52 / 43.37 |
| 18 commits | 79.80 / 86.62 | 42.21 / 46.56 |
| 65 commits | 170.70 / 180.23 | 45.78 / 49.78 |

At 65 commits, median asynchronous refresh latency improved by **73.2%**.
This checkout's shallow bookmark case stayed essentially unchanged: 43.46 to
43.52 ms median (48.72 to 50.85 ms p95). This change targets deep bookmark searches;
the Git implementation is unchanged. Cold searches still expand as needed.

The counting-wrapper integration test covers expansion beyond 16 and 64
generations, one-process subsequent refreshes, shrinking after a closer bookmark,
deleting that bookmark, snapshotting edits and switching repositories.
All 39 integration tests pass against the Nix-built worker and compiled client,
including actual Powerlevel10k rendering. The generated Quicksilver `.zshrc`
builds and passes syntax checking; `./utils/flake-check.sh` passes.
Configuration was not activated.

Matched binaries, the paired benchmark driver and raw samples are saved in
`/tmp/jj-prompt-depth`. The existing standalone benchmark now accepts `--depth`
to reproduce distant-bookmark fixtures:

```bash
set -euo pipefail
GIT_STATUS_DAEMON=/tmp/jj-prompt-depth/after \
  python3 tests/benchmark-jj-status-daemon.py \
  --tracked-remote --depth 65 --samples 40
```

## Preserve query plans across repository changes

The worker now retains bookmark names and ancestry window sizes for the 32 most
recently used JJ repository roots. Subdirectories share their repository's plan.
Returning to a previously visited repository can therefore use one snapshotting
query instead of restarting the ancestry search and upstream lookup. Names,
changes, conflicts and divergence are still recomputed on every request; cached
plans are verified against the fresh graph. First visits and evicted repositories
use the normal cold lookup.

Measured 2026-11-13 with both workers compiled using Rust 1.95.0, edition 2021,
optimization level 3 and stripped symbols. One persistent worker per version
alternates between two synthetic repositories with different tracked bookmark
names, one 65 commits behind its working copy and the other one commit behind.
After ten warmup pairs, 40 pairs were measured in randomized worker order. Every
reply was byte-identical. These timings measure asynchronous refresh availability.

| Returning to repository | Before median / p95 (ms) | After median / p95 (ms) |
| --- | ---: | ---: |
| Bookmark 65 commits back | 180.46 / 225.52 | 39.33 / 45.48 |
| Bookmark 1 commit back | 70.51 / 79.89 | 36.85 / 42.63 |

The deep case improves by **78.2%**, reducing five JJ processes to one on return.
The shallow case improves by **47.7%**, reducing two processes to one. This targets
repository switching; refreshes that stay in one repository already use one query.

The counting-wrapper integration test covers returning through a subdirectory,
alternating repositories, and invalidating a cached plan when a bookmark changed
while visiting another repository. Matched binaries, the paired benchmark driver
(`switching.py`) and raw measurements (`switching.json`) are saved in
`/tmp/jj-prompt-query`.

Twenty-five randomized paired requests per non-repository, small clean Git,
large dirty Git and checkout fixture also returned identical bytes. Staying in
this checkout was essentially unchanged: 38.23 to 38.47 ms median. Git medians
were 10.85 to 11.07 ms outside a repository, 41.58 to 41.73 ms for small clean Git,
and 418.73 to 395.77 ms for large dirty Git. Raw samples are in `regression.json`.

All 39 integration tests pass against the Nix-built worker and compiled client,
including actual Powerlevel10k rendering. The generated Quicksilver `.zshrc`
builds and passes syntax checking; Rust formatting and `./utils/flake-check.sh`
pass. Configuration was not activated.
