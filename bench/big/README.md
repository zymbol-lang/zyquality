# bench/big/ — long programs, and the curves that found what is slow (ZyBigBench)

The programs one level up mostly finish in under 30 ms, which is inside the noise
of starting a process. These run for 0.1 to 1.5 s on the VM, and each has a
Python twin that prints **exactly** the same thing, so the twin is an oracle for
the result before it is a reference for the time.

They come from ZyBigBench, a measurement made in another session — a claude.ai
account of its own, in a 4 GB container — between 2026-10-10 and 2026-10-13, and
were brought here on 2026-10-14. Its findings log is `HALLAZGOS.md`, kept
verbatim and in Spanish, like every findings log in the workspace.

## Four runners, four questions

| Runner | Question | Time unit | Exact unit |
|---|---|---|---|
| `run.py` | What does a whole program cost, against Python? | The process, start-up subtracted | `--count` of the whole run |
| `gap.py` | How far is each operation from Python, and does the gap grow with n? | The operation alone | `--count` steps of the operation alone |
| `scaling.py` | Does an operation grow as it should — linear, or one per call? | The exponent `b` of `y ~ n^b` | `b` in steps and in bytes too |
| `langs.py` (+ `langs_page.py`) | What does each program cost in other languages, and in each Zymbol engine? | The process, start-up included, per language | instructions where `perf` allows |

## Other languages — `langs.py` (2026-10-18)

Every program has a twin in `pl/` (Perl), `php/` (PHP), `lua/` (Lua), `rb/` (Ruby), `js/` (Node) and
`jl/` (Julia) beside the one in `py/`, written as the Python twin is — same algorithm, same shape, same
printed line — and `langs.py` keeps no figure from a twin whose line differs from Python's. Python,
Perl, PHP, Lua and Ruby are interpreters, as Zymbol is (PHP's opcache JIT is off on the command line,
Ruby's YJIT needs `--yjit`); Node and Julia are JIT compilers and are the reference of what compiling
buys. Julia's twins wrap their code in `main()`, because a global in Julia is untyped. Each figure
is recorded as elapsed time and as CPU time (the kernel's user + system accounting of the child,
`wait4`, which needs no privilege); instructions are added where `perf` may count them. Elapsed time
leads: Julia compiles on other threads while it starts and spent 2.8× as much CPU time as elapsed
time, so in CPU time it was charged for work no one waits for — the first version of the page did
exactly that. Start-up is measured on an empty program per language (Julia's is 185 ms), and the page
also shows each figure with it subtracted, over the programs Zymbol takes 100 ms or more on.

`langs_2026-10-18.json` is the run behind the site's benchmarks page (zymbol-lang.org/benchmarks.html),
176 of 176 twins agreeing, with `ZYMBOL_OLD` set so the four Zymbol engines are in it — v0.0.11's VM
and tree-walker, v0.0.10's VM and tree-walker. `langs_page.py` writes the page and its Markdown twin
from it; the page lets the reader pick any language or engine as the reference. Geometric mean of
elapsed time with Zymbol v0.0.11's VM (`7ef269c`) = 1.00: Node 0.46, PHP 0.63, Lua 0.64, v0.0.10's VM
1.68, Perl 1.70, Julia 1.76, Ruby 1.77, Python 1.84, the tree-walkers 7.2–7.5. Start-up subtracted
(11 programs, against the same reference): Node 0.11, Julia 0.14, PHP 0.38, Lua 0.45, Ruby 0.83,
Zymbol 0.99, v0.0.10's VM 1.41, Perl 1.64, Python 1.65.

## The instruments — the project's own, in `instruments.py`

The three runners measure with what `cost/` and `ZyDDT/HALLAZGOS` measure with,
and not with a clock of their own:

- **`zymbol run --count`** — steps, calls, allocs, bytes, copied. Exact: the same
  on every run and every machine, so one run answers, and a before/after in these
  units is the one to quote. It is what `cost/` asserts its growth ratios in.
  Python has nothing like it, so it only ever describes the Zymbol side.
- **`perf stat -e instructions:u`**, median of 7 (3 for a curve) — the unit the
  findings in `ZyDDT/HALLAZGOS` quote. It sees everything the process executes,
  Python included, which is what makes it the unit for comparing the two. It
  needs `kernel.perf_event_paranoid` at 2 or lower:
  `sudo sysctl kernel.perf_event_paranoid=1`, and back to its value afterwards.
- **Where perf is not allowed**, the time unit falls back to CPU ms (`run.py`,
  `scaling.py`) or to each program's own timer (`gap.py`), and the first line of
  the report says so. A table never mixes the two, and a clock figure is never
  printed under an instruction heading. `--clock` forces the fallback.

`gap.py` isolates an operation by subtraction in instructions — the program
minus the same program with the hot part left out — and does the same in
`--count` units, where the subtraction is exact. With the clock it reads the
program's own timer instead, which already leaves the setup out.

**First run in instructions, 2026-10-14** (`perf_event_paranoid=1`): 16 of 16
programs and 108 of 108 operation values agree with Python in both engines; the
VM's spread over 7 runs was 0.00 %, the tree-walker's 0.2 %. Every healthy curve
in `scaling.py` fits `b = 1.00`, and the ones it marks are exactly the open
findings — with no `noisy` row, and without the clock's false positive on
`dict_update_existing`. Instructions are not time: on the VM the sixteen
programs come out at 1.02× Python in instructions and 0.86× in CPU time.

**Stage 2 measured, 2026-10-17** — CPU time (`perf` was locked, `perf_event_paranoid=3`), the
VM, against `b49fc26` (the branch when stage 2 began, built here with the same profile) and
against the official v0.0.10 `.deb` binary, each pair interleaved in one session. `run.py`: 16 of
16 programs agree with Python; geometric mean of the 15 compared, after/before — cpu-ms **0.842**
against `b49fc26` and **0.785** against v0.0.10, bytes **0.784**, steps 1.000. The gain is the
string programs: `strings_scan_long` 487 → 42 ms (bytes 90.4 MB → 2.6 MB), `strings_scan_short`
140 → 70 ms; the rest move within the clock's ±10 %. Zymbol/Python over the 13 programs above
50 ms: **0.80**. The tree-walker is unchanged (1.07, noise) — stage 2 did not aim at it.

`gap.py`, 27 operations, every value equal to Python's in both engines, VM at 2n:

| operation | before | after | after/before | growth ×2n, before → after |
|---|---:|---:|---:|---|
| `str_iter` (PERF-04) | 1 025 ms | 24 ms | 0.02 | 4.00 → linear |
| `dict_lookup_last` (PERF-03) | 202 ms | 4 ms | 0.02 | — |
| `dict_insert` (PERF-03) | 102 ms | 7 ms | 0.07 | 2.91 → 1.75 |
| `str_concat` (PERF-06) | 264 ms | 26 ms | 0.10 | 6.77 → 2.36 |
| `str_slice_small` (PERF-05 a) | 146 ms | 17 ms | 0.12 | — |

Two things it found that were not wins. **A call got dearer**: the depth limit of GLB-133 read the
thread's stack on every call, ~8 % of a loop of 3 000 000 one-line calls; the direct call does not
recurse in Rust, so the check was dropped there and kept where `$>` re-enters the loop — ~4 % is
left, inside the clock's reach and not attributable without `perf`. And **`s$#` over a 147 KB
ASCII text** runs ~18 % slower, 200 000 times over: the same code and the same steps, so the
compiled dispatch loop and not `StrLen` — the scan itself is PERF-05 b, deferred by D8, whose fix
would make it O(1). `bench/baseline.txt` (2026-10-09) passes 16 of 16; its `vm/bench_recursion`
reads +15 % against a figure of another day, and interleaved with `b49fc26` the two are equal.

**Stage 2, later on 2026-10-17, in instructions** (`perf_event_paranoid=1`, median of 7, VM): `d1c9554` (the
branch that morning) against `71141c1`, each against its Python twin. The counted loop in one instruction
(`RangeStep`, ZYVM-029), `$>`/`$|`/`$<` on the VM's frames (`HofNext`), no `LoadUnit` before a `Return`, and a
call that pushes its frame inline. Every program still prints what its twin prints. Above Python: `tak` 1.27,
`sort_cmp_300k` 1.25, `fib_rec` 1.10, `nqueens` 1.06 — what is left is the cost of a call.
Later the same day, `call_callable` writing its arguments in place and option B — `$^` evaluating a comparator
that is a comparison of its parameters without a call — took `sort_cmp_300k` to **0.69** of Python
(`30ad8ae` −9.8 %, then −39.0 %).

| program | before | after | after/before | before / Python | after / Python |
|---|---:|---:|---:|---:|---:|
| `array_update` | 18M | 10M | -41.5% | 0.45 | 0.26 |
| `collatz` | 4509M | 4495M | -0.3% | 0.45 | 0.45 |
| `fib_rec` | 10846M | 9960M | -8.2% | 1.19 | 1.10 |
| `hof_chain` | 4042M | 3819M | -5.5% | 1.01 | 0.95 |
| `loop_mod` | 9411M | 6211M | -34.0% | 0.49 | 0.32 |
| `mandelbrot` | 2809M | 2792M | -0.6% | 0.36 | 0.36 |
| `match_loop` | 4431M | 3324M | -25.0% | 0.68 | 0.51 |
| `matmul` | 4533M | 3427M | -24.4% | 0.51 | 0.39 |
| `nqueens` | 3478M | 3399M | -2.3% | 1.08 | 1.06 |
| `primes_trial` | 2801M | 2710M | -3.2% | 0.36 | 0.35 |
| `sort_builtin` | 1028M | 835M | -18.7% | 0.63 | 0.52 |
| `sort_cmp_300k` | 6073M | 5840M | -3.8% | 1.30 | 1.25 |
| `sort_cmp_4k` | 53M | 50M | -4.6% | 0.60 | 0.57 |
| `strings_scan_long` | 389M | 388M | -0.3% | 0.72 | 0.72 |
| `strings_scan_short` | 773M | 772M | -0.1% | 0.80 | 0.80 |
| `tak` | 5256M | 4628M | -12.0% | 1.45 | 1.27 |

**What `--count` cannot see, and why each runner carries both.** A scan inside
one instruction is one step whatever the length of what it scans. `scaling.py`
says so per curve: when the time grows faster than expected and neither steps
nor bytes does, it reports the finding as `blind` — a `cost/` case for it has to
be asked by the clock — and when one of them grows too, it names which, and the
case can be asked exactly. On 2026-10-14: `str_iter`, `dict_insert`,
`dict_lookup_last` and the VM's `str_len` are blind; `str_concat`,
`str_slice_small` and the tree-walker's `str_len` show in bytes. In
`strings_scan_long` the VM executes ~1 300 instructions per step where
`fib_rec` executes ~110: that is the `is_ascii()` of PERF-04, and only
instructions see it.

With the clock, a `percall` curve is the difference of two runs, and when the
operation is small beside building its structure that difference is noise: the
first key of a dictionary updated 2 000 times fitted `b = 1.18` while a timer
inside the program read 2–3 ms at every size. So a clock curve whose points do
not rise one by one, or whose net is under a tenth of what was subtracted from
it, is reported as `noisy` and does not fail the run. Real findings land there
too — the tree-walker's `str_len`, the VM's `dict_lookup_last` — which is why
`gap.py`'s timer, or instructions, have the last word on them.

```bash
# from zyquality/bench/big/ — ZYMBOL_BIN chooses the binary, as in bench_gate.sh
python3 run.py                                   # 16 programs, VM
python3 run.py --engine tw --only fib_rec,tak
python3 gap.py                                   # 27 operations at n and 2n, VM and tree-walker
python3 gap.py --only str_iter,dict_insert --runs 5
python3 scaling.py                               # 28 curves; takes the better part of an hour
python3 scaling.py --only str_concat --no-tw
ZYMBOL_OLD=/path/to/other/zymbol python3 run.py  # before/after, same engine
python3 run.py --clock                           # CPU time even where perf is allowed
```

`run.py` is registered in `suites.toml` as `bigbench`, not a gate: `zyq suite
--only bigbench`.

**The result is checked before the time is compared.** `run.py` compares each
program's whole output with its twin's and exits 1 on a difference; `gap.py`
compares the value every operation prints, in both engines, and exits 1 on a
difference. `scaling.py` has no oracle — it measures shape, not value — and exits
1 when a curve grows faster than expected, which on the day it was brought here
it did, for the open findings below.

## `gap.py` versus `scaling.py`

They ask about the same operations in two ways: `gap.py` at two sizes and
against Python, `scaling.py` at four and against the expected exponent. For a
`percall` operation `scaling.py` subtracts a run with K = 0. In CPU ms that
subtraction is noisy when building the structure takes seconds — ZyBigBench's
first pass reported `dict_lookup` at `b = 2.23`, which was noise, and on
2026-10-14 two runs of the same binary gave it −0.19 and 0.86 — while in steps
and bytes it is exact. What the clock alone says is confirmed with a timer
inside the program, as in `confirmaciones/`, or in instructions.

## `confirmaciones/`

Minimal programs, each with a timer inside, that confirm one finding apiece.
They take their sizes as arguments: `zymbol run --vm confirmaciones/str_t.zy
294912`. `asignador_c/` is two C programs that reproduce, outside Zymbol, the
cost of musl's allocator against glibc's; `LEEME.txt` says how to build them.

## The findings, and where they are

| `HALLAZGOS.md` | State on `v0.0.11` (2026-10-14) |
|---|---|
| PERF-01 `v[i]$~ x`, VM | Fixed in `ee48143` (2026-10-10, ZYVM-013); held by `cost/` `growth/update-local` |
| PERF-02 `v = v $-[i]`, VM | Fixed in the same commit |
| PERF-03 dictionary lookup is linear, both engines | Fixed 2026-10-16 as GLB-131 (a key written twice is refused) and GLB-132 (an IndexMap; zyjs too); held by `cost/` `growth/dictionary-by-key` |
| PERF-04 `@ ch:text` is quadratic, VM | Fixed 2026-10-16 as ZYVM-025; held by `cost/` `growth/foreach-over-text` |
| PERF-05 `s$#`, `s$[a..b]`, `s[i]` cost the length of the string, both engines | **a**, the copy, fixed 2026-10-16 as GLB-130 (`cost/` `growth/slice-a-text`); **b**, the scan, deferred by D8; the tree-walker's copy on every read filed as ZYTW-016 (`growth/read-a-text`). Before: More than a scan: `s$[a..b]` copies the whole string into a `Vec<char>` before cutting (VM `StrSlice`, tree-walker `collection_ops.rs`), so a 10-character slice of 73 728 asks the allocator for 516 KB on the VM and 590 KB on the tree-walker — `--count` bytes, exact. And the tree-walker's `s$#` asks for exactly n bytes per call: it copies the string to measure it |
| PERF-06 `s = s "x"` is quadratic, VM | Fixed 2026-10-16 as ZYVM-023; held by `cost/` `growth/concat-local`, `growth/concat-in-function` and `growth/concat-module-state` |
| PERF-07 deep recursion aborts the process (exit 134), no Zymbol error | Fixed 2026-10-16 as GLB-133 (D7: a catchable `##Depth` at 10 000 active calls, in the three engines); held by `corpus/errors/runtime/depth_*.zy` |
| PERF-08 the static musl binary, up to 11× slower | Reproduced 2026-10-16 with v0.0.10's two official x86-64 binaries (SHA-256 verified), filed as GLB-134: `str_concat` ×17, `str_slice_small` ×4.6, interpolation and closures ×1.3, the 16 programs ×1.005. The current `HEAD` is not measured — no musl target here |

"Not filed" means the author has not yet decided, per finding, whether to fix,
defer or dismiss it; until then none has a ZyDDT entry or a `cost/` case.

## What changed from ZyBigBench's copy

- **The sixteen programs, their twins and `confirmaciones/` are unchanged.** So
  are the operation tables inside `gap.py` and `scaling.py`, but for one row
  added to each: `dict_lookup_last`. `dict_lookup` reads the key inserted
  **first**, which a linear search finds at once, so it read as flat while the
  lookup was linear — `HALLAZGOS.md` retracts its own conclusion over exactly
  that. The new row reads the last key: 52× Python at 4 000 keys on the VM,
  where `dict_lookup` reads 2.8×.
- **The three runners are rewritten in English**, with the same logic and three
  corrections:
  - **Every engine is named.** ZyBigBench ran `zymbol run FILE` for the
    tree-walker, which was right on v0.0.10. Since v0.0.11 a bare `run` is the VM,
    so its tree-walker column would have measured the VM twice. The same mistake
    was in `../python/measure.py --engine tw`, and was fixed with this.
  - **They write to a temporary directory** of their own instead of `/tmp/zygap`
    and `/tmp/zyscale`, and resolve every path from their own location.
  - **They return exit codes** (0, 1, 2 as above) instead of always 0, so a
    disagreement with the oracle is a failure and not a line in a report.
  - `run.py` takes `--engine`; it only knew the VM.
- **They measure in the project's units** (2026-10-14), described above. The
  original timed everything by the clock — CPU time of the process, or the
  program's own timer — which is a third instrument nothing else in
  `zyquality/` or ZyDDT quotes. The clock is kept only as the fallback where
  perf is not allowed.
- **The results files are not here.** `resultados_*.txt` and `.json` are one
  container, one binary and one Python; `HALLAZGOS.md` quotes the figures that
  matter, with their dates. Re-measure before quoting one.

## Limits

- **The Zymbol timer prints whole milliseconds.** A gap whose Zymbol side is
  under 5 ms is printed as `~`: a bound, not a value.
- **Idiomatic twins, not identical ones.** `array_update.py` preallocates where
  the Zymbol program appends; the sorts use `cmp_to_key` so that each call is
  compared with each call. The same result, not the same cost model.
- **One machine, for the time unit.** Instructions travel better than
  milliseconds but still depend on the binary and the CPU; the `--count` units
  depend only on the binary.
- **`perf stat` answers 0 for a child killed by a signal.** It passes on an
  ordinary exit code, but a tree-walker that aborted on its stack (134) came
  back as a successful measurement. `instructions()` therefore runs the program
  once without perf and takes its exit status from that run.
