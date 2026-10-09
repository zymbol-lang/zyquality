# bench/python/ — the bench/ programs against Python (ZyBench)

Python ports of 9 of the 12 programs in `bench/`. Each port does the same work as
its Zymbol program and prints the same lines — a label that carries the result,
then the elapsed time — so it is two things at once:

- an **oracle** for the result: an implementation that is not ours, and that has
  to print the same `fib(30) = 832040` Zymbol prints;
- a **reference** for the time: how long Python takes for the same work.

They come from ZyBench, a measurement made in another session between 2026-10-04
and 2026-10-07, and were brought here on 2026-10-09. Its findings log is
`HALLAZGOS.md`, kept verbatim and in Spanish, like every findings log in the
workspace.

## Running them

```bash
# from zyquality/bench/python/
python3 measure.py                                  # VM, general group, median of 3
python3 measure.py --engine tw --group text --runs 5
python3 measure.py --group all --json out.json      # also write the results
ZYMBOL_BIN=../../../interpreter/target/release/zymbol python3 measure.py
```

`--group general` is recursion, collections, match, numeric and higher-order
functions; `--group text` is the four string programs; `--group all` is both.

**The result is checked before the time is compared.** For every timed line the
label of the Python port has to equal the label of the Zymbol program, in every
run. A line that differs prints `RESULT DIFFERS` with the Python label under it,
and `measure.py` exits 1. That check was made to fail on purpose before it was
trusted: a copy of `bench_recursion.py` changed to compute `fib(29)` gave
`29 of 30 results agree` and exit 1.

A ratio is Zymbol's time over Python's: below 1, Zymbol is faster. When either
side ran under 10 ms the ratio is printed with `~` (or as `bound` when Python
measured 0): the timers print whole milliseconds, so it is a bound, not a value.

## What it gave here, 2026-10-09

`zymbol 0.0.10` from this repository's release build, Python 3.13.5, one run:
**65 of 65 results agree** on the VM, and the text group's 35 agree on the
tree-walker too. Times are not recorded here on purpose: they are one machine,
one load and one binary — re-measure before quoting one.

## What changed from ZyBench's copy

- **The nine ports and `_t.py` are unchanged.**
- **`measure.py` is rewritten.** ZyBench's took the paths of the machine it ran on
  (`/home/claude/apps/zyquality/bench`, `/home/claude/bench/py`), wrote to `/tmp`,
  and measured Python and Zymbol in separate invocations. Its `LEEME.md` said it
  *"discards any test whose result does not match Zymbol's"*; it compared nothing.
  This one resolves every path from its own location, takes the binary from
  `ZYMBOL_BIN` like `bench_gate.sh`, runs both sides in one invocation and makes
  the comparison it used to claim.
- `LEEME.md` is replaced by this file.

## What is not here

The log refers to files that were not brought: `ordenar_comparador.patch`,
`vm_llamadas.patch`, `NOTAS_orden_comparador.md`, `NOTAS_optimizaciones_vm.md`,
`corpus/33_sort_custom_stable.*`, `corpus/34_sort_custom_large.*` and `prof/`.

Where each finding went:

| ZyBench | filed as |
|---|---|
| `BUG-BEN-001`, the comparator sort | `GLB-108` (`ZyDDT/HALLAZGOS/GLOBAL.md`), held by `cost/` `growth/sort-with-comparator` |
| `IDEA-BEN-002`, the call frame | evidence in `ZYVM-010` (`ZyDDT/HALLAZGOS/zyvm.md`) |
| `IDEA-BEN-003`, the measurement | `notes/VM_VS_PYTHON.md`, and this directory |
| `ERROR-BEN-004`, the documents' claims | `notes/VM_VS_PYTHON.md`; `web/install.md` corrected 2026-10-09 |

## Limits

- **9 of 12.** `bench_index_read`, `stress`, `bench_pipeline` and
  `bench_recursion_loop` have no port.
- **Idiomatic, not identical.** The ports `append` where Zymbol writes `a$+ x`:
  the same result, not the same cost model.
- **Not a gate.** Nothing in `suites.toml` runs this: it reports wall time on one
  machine against one Python, which is a measurement, and `bench/` already gates
  each program against its own baseline. Whether to hold the *results* — the
  oracle half, which is machine-independent — in a gate is a separate decision.
