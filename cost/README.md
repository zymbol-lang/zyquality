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
| `NO VERDICT` | it could not be measured — usually a base run below `min_base_ms`, where the ratio would be measuring process startup |

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

## What is open

| finding | case | measured |
|---|---|---|
| [`ZYVM-003`](../../ZyDDT/HALLAZGOS/zyvm.md) | `growth/append-module-state` | 19.6 where the tree-walker is 3.8 |
| [`ZYJS-014`](../../ZyDDT/HALLAZGOS/zyjs.md) | `growth/append-local` | 12.9 where both Rust engines are ~3.3 |
