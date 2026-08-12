# bench/ — programs that are measured, not compared

Everything here prints elapsed wall time. That makes these programs useless to
`zyq consensus`, which asks whether the engines produce the same output: they
never can, and the difference *is* the point.

So they are here rather than in `corpus/`. That is not a filing preference. A
file the corpus can never compare costs three things to keep there — an
exclusion rule to silence it, a golden nobody can check, and a line in every
report that has to be explained away — and pays for none of them.

## What was wrong before

These twelve programs were in three places at once:

- `interpreter/tests/scripts/` — seven `bench_*.zy`, `stress.zy`, an orphan
  `_test_fib_approaches.zy` that no script referenced, and `lib_time.zy`
- `zyquality/corpus/stress_v2/` — four more
- `lib_time.zy`, the timing module they all import, in **both**, byte-identical

Of the four test suites in the project, three could not see them: the
interpreter's runners all excluded `*/scripts/*`, and zyml's parity excluded
them with `grep -L lib_time`. The one that did run them was
`web/tests/test_runner.mjs` — where all ten failed, and were counted as
divergences of the JavaScript engine. `web/README.md` reported them as
"10 failing" for as long as anyone had been reading it.

## Running them

```bash
# from interpreter/ — the binary they measure lives there
bash tests/scripts/run_all.sh                 # one pass
bash tests/scripts/run_all.sh --vm --runs 5   # both engines, median of 5
bash tests/scripts/bench_gate.sh              # gate against the baseline
bash tests/scripts/bench_gate.sh --record     # (re)write the baseline
```

The baseline stays in `interpreter/tests/scripts/bench_baseline.txt`, and that
is deliberate: it is wall time measured on one machine against one binary, so
it belongs to the thing being measured rather than to the corpus. Record it on
the same machine that will enforce it.

`bench_gate.sh` takes the **median** of five runs. Running it with `--runs 1`
reports whatever the machine was doing at that moment — a benchmark showed a
37% regression that way while the machine was busy, and none at the default.

## The `.expected` files in `stress_v2/`

They are kept even though nothing checks them today. They record the *operation
counts* (`T1_template_build: total=198393`) alongside `***time***` markers for
the timings, so they say something a benchmark should say: that the program did
the same amount of work, not merely that it finished. `zyq bench` (phase 4) is
where they get read.

## Adding one

Drop the `.zy` here and add it to `BENCHES=(…)` in `bench_gate.sh`, then
`--record` a baseline. It imports the timer as a sibling:

```zymbol
<# ./lib_time => T
```

`stress_v2/` is one level down, so it uses `<# ../lib_time => T`.
