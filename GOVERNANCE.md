# The point of record

Zymbol has three engines in three repositories. **They are graded here, against
one corpus, under one set of rules.** This document says what that commits each
repository to.

> There were four until 2026-08-17, when `zyml` — the OCaml closure-compiling
> engine — was retired. It could not run 131 of the 599 corpus files and
> diverged on 15 more, while the two Rust engines diverge on zero, and its speed
> case did not survive real load (3.4× slower than the register VM at 19×19 go,
> after copy-on-write). Its repository is archived and `zyml/DEPRECATED.md` has
> the numbers. **This document keeps its history**: `corpus/arity/` and
> `corpus/loops/labels/` exist because of it, and a rule whose reason has been
> deleted is indistinguishable from one nobody can justify.

## The rule

> A change to any engine is validated against ZyQuality. A suite that grades an
> engine against files it owns itself is not a gate — it is that engine's
> opinion of itself.

Concretely:

| repository | its gate | what it runs |
|---|---|---|
| `interpreter` | `bash tests/scripts/vm_compare.sh` | `zyq consensus --engines zytw,zyvm` |
| `web` | `node tests/test_runner.mjs` | `zyq consensus --engines zytw,zyjs` |
| the project | `zyq suite` | all of it, one verdict |

`zyq suite` is the whole thing: selftest, corpus hygiene, rejections, goldens,
consensus, and then the script suites registered in `suites.toml` — the
formatter audit, the pty harness, the GUIDE verification, the benchmark gate.
`zyq suites` lists them and says what each needs; `zyq suite --only bench` runs
one, which is what a CI runner that owns the benchmark baseline wants.

Each repository's own script keeps its name, its flags and its exit codes. They
are wrappers. They exit **2** when ZyQuality is absent — never 0, because a gate
must not read "nothing ran" as "nothing failed".

## Why one corpus and not four

The corpus used to exist twice, in `interpreter/tests/` and here, and the copies
had drifted 28 files apart. The missing ones were `arity/` and `loops/labels/` —
the files v0.0.9 added *because the four engines disagreed about labels*. They
were tested by one runner and invisible to the other three.

Underneath that, each runner carried its own idea of which files it could not
compare: a `@vm-skip` marker, a 40-entry `SKIP_SET` literal inside JavaScript, a
`grep -L lib_time`, and nothing at all. None could read the others. A file
excluded from the browser comparison because it shells out was still counted as
a divergence by zyml.

Three concrete things were invisible until the four engines were put in one
place, and all three were found on the first sweep:

- **The browser engine accepts `m[1][2] = 77`.** It runs the line, changes
  nothing, exits 0. The CLI rejects it with five errors. A silent no-op is worse
  than a program that does not compile, and no suite could see it, because
  consensus compares what programs *print* and a refused program prints nothing.
  That is what `reject/` is for.
- **47 goldens carried the path the corpus had when they were recorded** —
  `tests/arity/x.zy:8:1`, or an absolute `/home/…`. They passed in exactly one
  checkout, on one machine, run from one directory. `zyq` strips the corpus root
  before comparing, so a golden now says the same thing everywhere.
- **The typed golden wildcards silently degraded.** `***int***` was a Python
  regex, and without `python3` the runner fell back to a plain glob — turning
  "an integer goes here" into "anything at all goes here", on the machine least
  likely to be checked. `zyq` has no fallback because it has no dependency.

## The whole map

Everything that answers a question about the language is here. Nothing that
does is anywhere else.

```text
zyquality/
    zyq                 the differential runner (OCaml, no dependencies)
    corpus/             585 .zy, 583 with a .expected golden
    corpus.toml         who may be judged on what, and why not
    reject/             forms every engine must refuse
    suites.toml         the script suites, so `zyq suite` runs them too
    fmt/                formatter properties P1-P4 + its baseline
    tui/                key input through a real pty + its cases
    bench/              benchmark programs, their runners and baseline
    docs/               GUIDE.md example verification
    project/            the real programs written in Zymbol
        apps.toml       where each application's suites live
        run.sh          drives them through zyq: goldens gate, engines report
    platform/           the native Windows runner (no bash, no WSL)
    notes/              historical measurement records
    cases/              external oracles (phase 3)
```

| was | is |
|---|---|
| `interpreter/tests/**/*.zy` + `.expected` | `corpus/` |
| `interpreter/tests/scripts/vm_compare.sh` | `zyq consensus --engines zytw,zyvm` |
| `interpreter/tests/scripts/engine_compare.sh` | `zyq consensus` |
| `interpreter/tests/scripts/expected_compare.sh` | `zyq expect` |
| `interpreter/tests/scripts/semantic_compare.sh` | `zyq expect --via check` |
| `interpreter/tests/scripts/fmt_property.sh` | `fmt/fmt_property.sh` |
| `interpreter/tests/scripts/fmt_idempotency.sh` | `fmt/fmt_idempotency.sh` |
| `interpreter/tests/scripts/bench_*.zy`, `stress.zy`, `lib_time.zy` | `bench/` |
| `interpreter/tests/scripts/run_all.sh`, `bench_gate.sh` | `bench/` |
| `interpreter/tests/scripts/guide_verify.py` | `docs/` |
| `interpreter/tests/scripts/run-project-tests.sh` | `project/` |
| `interpreter/tests/scripts/run-tests.ps1` | `platform/` |
| `interpreter/tests/scripts/*.md` | `notes/` |
| `zyml/tests/cases/*.zy` | `corpus/smoke/` (kept: 22 files that outlived the engine) |
| `zyml/tests/ptydrive.py`, `tests/tui/` | `tui/` (kept: the pty driver is engine-agnostic) |
| `zyml/tests/parity.sh` | retired with the engine, 2026-08-17 |
| `GO/試験/全試験.sh`, `serpiente/pruebas/todas.sh`, `klingon_galaxy/mIw/Hoch.sh` | `project/run.sh` (the suites stay; the verdict moved) |
| `zyml/tests/rejects.sh` | `zyq reject` |
| `web/tests/test_runner.mjs` | `zyq consensus --engines zytw,zyjs` |

What stayed, and why:

- **`web/tests/run_one.mjs`** — the driver for the JavaScript engine. It belongs
  with the engine it drives; `engines.toml` points at it. ZyQuality had a copy
  that skipped the static-check pass, and deleting that copy fixed 14 files.
- **`web/tests/test_*.mjs`** (licences, Markdown twins, catalog, DOM, symbols,
  i18n, `.zyp`, limits) — they grade a website, not the language.
- **`interpreter`'s 969 `#[test]` functions** — they live inside the crates and
  test units rather than behaviour. `cargo test` is unaffected.
- **`interpreter/examples/`** — that repository's own example programs.
  `fmt/fmt_property.sh` sweeps them when the checkout is there.
- **The application test suites** — `GO/試験/`, `serpiente/pruebas/`,
  `klingon_galaxy/mIw/`, `Zofia/tests/`, `ZyAudit/测试/`. A suite imports the
  application it tests (`<# ../核/盤 => 盤`); move the file and the import points
  at nothing. Their goldens sit beside them, which is what Zofia already did and
  the only arrangement where `zyq expect` finds a pair. What moved here is the
  registry, the runner, and the verdict — `project/apps.toml` and
  `project/run.sh`, gated by `zyq suite`.

Every other repository keeps a script with the old name that delegates here.

## What lives here and what does not

**Here.** Anything that answers *does the language behave correctly, and do the
engines agree*: the `.zy` corpus, the `.expected` goldens, the rejection corpus,
the exclusion rules, the redactions, the wildcard table, and the runner. The
benchmark programs are here too, in `bench/` — but outside the corpus, because a
program that prints elapsed wall time can never be compared, and a file the
corpus can never compare does not belong in it.

**Not here.** Tests of a *product* rather than of the language. `web/` keeps its
own suites for licences, Markdown twins, the example catalog, the DOM and the
playground's translations: those grade a website. `interpreter/` keeps its 969
Rust unit tests, which live inside the crates and test units, not behaviour, and
`fmt_property.sh`, which exercises a feature only one engine has. All of them
read the shared corpus where they need `.zy` files.

## Adding things

**A test.** Drop the `.zy` in `corpus/` — unless it prints elapsed time, in
which case it is a benchmark and belongs in `bench/`. Then record its golden and
read the diff:

```bash
./zyq expect --regen --new --engines zytw --filter your/new/file
git diff corpus/
```

**An exclusion.** A `[[rule]]` in `corpus.toml`, with a reason. The reason is
required: an exclusion nobody wrote a reason for is indistinguishable from a bug
somebody hid. If the file lives in another repository, put a `// @zyq-skip:`
marker in the file instead, so the rule travels with it.

**An engine.** A `[[engine]]` entry in `engines.toml`, never a patch to the
runner. If it cannot run something, declare the stderr prefixes it uses to say
so — a missing feature must be reported apart from a wrong answer.

**A rejection.** A `.zy` under `reject/` whose first lines say `// @reject: why`.
Earn its place: it has to be a form the language deliberately refuses, not
merely one that happens to fail today.

## What a red gate means

`zyq suite` is red today, and honestly so:

- `expect` — 584 of 584 goldens match, nothing unchecked.
- `reject` — 4 of 7 forms are refused everywhere. The three that are not are the
  `$~`-as-a-statement family, which the browser engine still runs. The three
  loop-specifier forms were added and closed in the same change; the fourth
  assignment form closed with them, for a reason worth recording: the browser
  engine *did* refuse it, but `runZymbol` catches its own errors so the
  playground can render them, and `tests/run_one.mjs` never read the result — so
  a refused program exited 0 and the gate scored it as accepted. A rejection
  suite that cannot see a rejection was measuring the runner, not the engine.
- `consensus` — 103 of 586 files diverge; **none where the tree-walker or the VM
  is the outlier.**
- `project` — two of Zofia's eleven suites error where their goldens record
  numbers: `forward_pass.zy` and `matmul.zy` now say *cannot access underscore
  variable from inner scope*. Those goldens were recorded when the programs
  worked. The per-project runners could not see it — they grep the output for
  `FAIL`, and a program that errors prints neither.

Each repository's own wrapper is scoped to its own engine, on purpose. A gate
that goes red for a defect in another repository is a gate its owner learns to
ignore. The four-engine question is `zyq suite`, and it belongs to the project
rather than to any one engine.

## Grading the grader

`zyq selftest` runs 51 checks over the pattern matcher, the globs, the golden
line matcher, the skip-marker parser and the two output filters — against cases
whose answer is known by reading them. It is the first step of `zyq suite`.

This is not ceremony. The two harness defects found while producing the first
consensus numbers — an argv list reversed by a double `List.rev`, and a missing
module resolver that made every `<#` import fail — both inflated the divergence
count, and neither was visible in the output. A bench that grades 585 files has
to be graded itself.

Two more came from this exercise. The in-file skip marker was read from the
first ten lines, and the first file to carry one had a fourteen-line header
explaining why — so it sat past the window and did nothing. And the legacy
markers `@vm-skip` and `@skip-parity` were read as "excuse every engine", when
each had lived in a two-engine runner where that reading is indistinguishable
from "excuse this one"; widening them removed a file from the four-engine
comparison that all four engines in fact agree on.
