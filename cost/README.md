# `cost/` — what a program may cost, as a ratio

Two questions nothing else in this repository can ask.

**Does auto-free still work?** It is required to be *invisible* — a correct
program prints the same thing with and without it — so its effect exists only in
the high-water mark of memory. The way to see it is a pair of programs that do
**identical work** and differ only in the **lifetimes** of their values:

| | | `zytw` | `zyvm` |
|---|---|---:|---:|
| two aggregates, used one after the other | subject | 236 MB | 38 MB |
| the same two, both alive at the last statement | control | 465 MB | 70 MB |
| | ratio | **0.51** | **0.55** |

With auto-free off, the subject *is* the control and the ratio is 1.00. The
declared limit is 0.70.

**Did something change complexity?** `bench/` runs each program at one size, so
a change from linear to quadratic reads as "slower" until the input grows and it
reads as a hang. Here the same program is run at `N` and at `N × 4`: linear is
4.0, quadratic is 16.0, and the limit sits between them.

**What does a function call cost?** The same Life generation written twice — a
neighbour count called once per cell, and the same count inline — run at one
size (`time-ratio`). Measured 2026-09-30: 1.14 under the VM, 0.87 under the
tree-walker. The limit, 1.30, guards the call path; it does not claim the 14 %
is understood — see the case's comment in `cost.toml` for what was measured and
what was not.

**Does a call cost what the function needs, or what it is long?** The same
function with one statement and with 64 in a branch that is never taken, so both
programs execute the same instructions (`time-ratio`). It is 1.0 where a frame
holds what is alive at once. Under the VM it was 2.76 until 2026-10-10, when its
frame held a register for every temporary the body ever asked for (`ZYVM-010`).

## Why ratios and not a baseline

`bench/baseline.txt` records milliseconds and says so in its own header —
*"machine-specific … host=zymbol"*. That is the right instrument for *did this
get slower*, and the wrong one for *does this mechanism still work*: the numbers
must be re-recorded on every machine, and re-recording is precisely the move
that makes a regression disappear.

Every case here carries its own control, measured in the same run, on the same
machine, seconds apart. A ratio survives a faster laptop, needs no baseline, and
cannot be quietly re-recorded: to move it you edit `cost.toml`, where the number
is read as what it is.

## Running it

```bash
./run.py                 # exit 0 green, 1 red, 2 no verdict
ZYMBOL_BIN=/usr/bin/zymbol ./run.py
```

## Reading the report

| tag | meaning |
|---|---|
| `PASS` | the ratio is within its declared limit |
| `FAIL` | it is not, and nobody wrote down why — a regression |
| `KNOWN` | it is not, and the case names an open finding: declared debt, printed in full every run, not counted against the gate |
| `SKIPPED` | a timed ratio whose base run fell below `min_base_ms`, for an engine that is also *counted* (`zytw`, `zyvm`): the counted ratios printed under it are exact and have no floor, so they answer the case — and the line says so, and says it too when they fail, because then they are the verdict |
| `NO VERDICT` | it could not be measured — a base run below `min_base_ms` on an engine nothing counts for (`zyjs`, a `count_off` case, a `time-ratio`), or counted ratios that could not be taken |

`KNOWN` is keyed by engine, because a finding belongs to an engine. And when a
`KNOWN` case starts passing the runner says so and asks for the finding to be
closed — an `open_finding` nobody removes is how debt becomes permanent.

## Sizes are per engine

One question, asked at the size each engine can answer it at (`n_by_engine`).
The Rust engines need hundreds of thousands of elements before a run is longer
than starting a process; the browser engine needs minutes at that size. Splitting
a case in two would make it two questions, and the day one was fixed nobody
would notice the other still asking the same thing.

**The faster the engine, the larger its case has to be** for its own ratio to
mean anything. `min_base_ms` is what refuses the measurement instead of
reporting a pass nobody should trust.

**What answers under the floor.** Sizes are calibrated on one machine, and a
CI runner two times faster than it puts the base runs of six cases under 40 ms
(GLB-128) — not because anything regressed. For `zytw` and `zyvm` the same case
is *also* asked in `--count` units, which are exact and have no floor, so a
timed ratio the floor refuses is reported `SKIPPED` and the counted ratios are
the verdict. Nothing is lowered: the floor is the same, and where nothing counts
— `zyjs`, a case with `count_off`, a `time-ratio` — the clock is the only
instrument there is, and an unreachable floor is still `NO VERDICT`. The `GREEN`
line says how many readings were set aside this way.

## What is open

One finding, declared as `KNOWN` since 2026-10-12: `ZYVM-022` (`autofree/call-result`, 1.8 under the VM — what a
call returns and the caller uses once stays in its temporary register until something reuses it). Before it,
nothing since 2026-10-10: `ZYTW-010` (`growth/module-call-that-writes-one-cell`, 13.8 under the tree-walker)
and `ZYVM-010` (`call/frame-as-large-as-every-temporary`, 2.76 under the VM) were declared here as `KNOWN` and
fixed that day; both cases are plain `PASS` now, and a ratio that climbs back is a regression.
