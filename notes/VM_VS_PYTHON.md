# The VM against Python — an outside measurement, and what the documents claim

> **Status (2026-10-08):** documented, not acted on. Nothing here changes code or
> a user-facing document; the author decides what follows. The engine findings
> the same measurement produced are filed in ZyDDT: the comparator sort as
> `GLB-108` (`ZyDDT/HALLAZGOS/GLOBAL.md`), the frame cost as evidence in
> `ZYVM-010` (`ZyDDT/HALLAZGOS/zyvm.md`).
>
> **2026-10-09:** the ports, a rewritten `measure.py` and ZyBench's log are now in
> `bench/python/` (its `README.md` says what changed and what was not brought), and
> `web/install.md` no longer gives a single factor.

## Where it comes from

ZyBench, a measurement made in another session between 2026-10-04 and
2026-10-07: Python ports of 9 of the 12 programs in `zyquality/bench/`
(`bench_recursion`, `bench_collections`, `bench_match`, `stress_v2/bench_numeric`,
`stress_v2/bench_hof`, `bench_strings`, `bench_strings_modify`,
`bench_strings_stress`, `stress_v2/bench_text`), 65 measurements whose results
agree with Zymbol's in all 65, under Python 3.12. Its log calls the comparison
`IDEA-BEN-003` and the documentation claim `ERROR-BEN-004`.

**In `bench/python/` since 2026-10-09:** the ports, a rewritten `measure.py` and
the log itself (`HALLAZGOS.md`). Re-run here that day, the 65 results agree with
Zymbol's in all 65 again, under Python 3.13.5. The
figures below that are ZyBench's are quoted as such; they were taken from the
published v0.0.9 VM and from builds of `820a60a` at opt-level 1 without LTO,
slower than this repository's release profile — a ratio between two of them
holds, a millisecond does not.

## What it found (ZyBench's figures)

VM time over Python time, published v0.0.9, tests above 10 ms (below 1 is a win):

| kind of work | tests | VM / Python |
|---|---:|---|
| integer loops and arithmetic (`N2`, `N4`, `N5`, `ackermann`) | 4 | 0.68 – 0.94 |
| calls and higher-order functions (`fib`, `H1`–`H5`, `H9`) | 7 | 1.70 – 3.00 |
| `??` by value, by range, nested | 3 | 1.83 – 2.33 |
| text (`bench_strings*`, `bench_text`) | 14 | median 3.00, loses all 14 |

The tree-walker's median was 14.3 (general) and 12.0 (text) times Python's.
A call or a lambda cost ~70–115 ns against Python's 33–47 ns. Two more
observations it left unexplained: string concatenation (`S1`) got ~11× faster
between v0.0.9 and v0.0.10 for a reason that was not looked into, and the
v0.0.10 tree-walker beat the published one on higher-order functions despite a
lower optimisation level.

## Checked here, 2026-10-08

The release build of `v0.0.10`, Python 3.13.5, wall time with process start-up
included, three runs each:

| program | VM | Python |
|---|---:|---:|
| recursive `fib(30)` | 221–222 ms | 119–145 ms |
| a 2 000 000-turn integer loop, `(s + (i * i) % 1000) % 1000003` | 243–250 ms | 276–288 ms |

The direction holds: the VM wins the integer loop and loses the call-heavy one by
1.5–1.8×. Nothing more was re-measured that day; since 2026-10-09
`bench/python/measure.py` repeats the whole comparison.

## What the documents claim

- `interpreter/MANUAL.md` line 121: *"VM: production, ~1.1–1.5× faster than
  Python for most workloads"*. This is ZyBench's `ERROR-BEN-004`. It holds for
  integer loops and not for calls, higher-order functions or text — but the file
  says at its top that it is **deprecated as of v0.0.5 and frozen at v0.0.4**,
  kept for historical reference only. Left as the record it is. No current
  document repeats the figure.
- `web/install.md` line 135: *"zymbol run --vm file.zy # register VM (~4×
  faster)"*. A single factor, where `CLAUDE.md` says there is none — 1.4–6.1× on
  the `bench/` microbenchmarks, more on search-shaped programs — and says to quote
  the workload. Its twin `web/install.html` does not carry the figure: the
  Markdown twin says something the page does not, which `web/tests/test_markdown.mjs`
  cannot see, since it compares versions, release URLs and digests only.
  Corrected 2026-10-09: the comment now reads *"register VM (faster; how much
  depends on the program)"*. The page has no command block at all, so there was
  no factor to align with — the twin stops claiming one. `web/changelog.md`'s
  *"~4× faster"* stays: it is the v0.0.x entry that introduced the VM, a record
  of what was measured then.
