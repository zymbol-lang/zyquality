<p align="center">
  <img src="logo.png" alt="Zymbol-Lang" width="180"/>
</p>

<h1 align="center">ZyQuality</h1>

<p align="center">
  The Zymbol project's point of record for testing.<br/>
  One corpus, four engines, one verdict.
</p>

<p align="center">
  <img src="https://img.shields.io/badge/version-v0.2.0-informational?style=flat-square"/>
  <img src="https://img.shields.io/badge/language-OCaml-e88b00?style=flat-square"/>
  <img src="https://img.shields.io/badge/license-AGPL--3.0-blue?style=flat-square"/>
  <img src="https://img.shields.io/badge/corpus-585%20files-brightgreen?style=flat-square"/>
  <img src="https://img.shields.io/badge/goldens-583-brightgreen?style=flat-square"/>
  <img src="https://img.shields.io/badge/engines-4-brightgreen?style=flat-square"/>
</p>

---

## Why this exists

Zymbol has four engines. Ask them all the same question:

```zymbol
>> (10 ^ 20) ¶
```

| zytw | zyvm | zyjs | zyml |
|---|---|---|---|
| `Runtime error: overflow` | `7766279631452241920` | `100000000000000000000` | `-1457092405402533888` |

Four engines, four answers, two of them plausible-looking numbers a program
would accept without complaint.

That was the first reason. The second is worse. Each engine had its own suite,
its own copy of the corpus and its own idea of which files it was allowed to
skip — so the corpus existed twice and had already drifted **28 files apart**,
and the missing ones were `arity/` and `loops/labels/`: the work v0.0.9 added
*because the four engines disagreed about labels*.

Everything now lives here, and every repository's test script is a wrapper over
`zyq`. The rules are in [GOVERNANCE.md](GOVERNANCE.md).

## Quick start

```bash
make
./zyq suite                          # the whole gate, one verdict
./zyq engines                        # what is installed, what is not
./zyq suites                         # the script suites and what each needs
./zyq consensus                      # the corpus through every engine
./zyq expect                         # the corpus against its .expected goldens
./zyq reject                         # forms every engine must refuse
./zyq audit                          # corpus hygiene
./zyq suite --only bench             # one script suite on its own
./zyq show corpus/path/to/case.zy    # what each engine said about one file
```

No dune, no opam switch, no external libraries — `ocamlopt` and `unix`, the same
as [zyml](../zyml). No `python3` either, which is the point: the typed golden
wildcards used to be Python regexes that silently degraded to a plain glob when
it was missing.

## What is in here

| | |
|---|---|
| `corpus/` | 585 `.zy` files, 583 with a `.expected` golden |
| `corpus.toml` | which engine may be judged on which file, and why not |
| `reject/` | forms every engine must refuse |
| `engines.toml` | how to run each engine |
| `suites.toml` | the script suites, so `zyq suite` runs them too |
| `fmt/` | formatter properties P1–P4, and its baseline |
| `tui/` | key input through a real pty — the one thing a pipe cannot test |
| `bench/` | benchmark programs and their gate — **not** tests, see below |
| `docs/` | verification of the annotated examples in `GUIDE.md` |
| `project/` | the registry and runner for the real programs written in Zymbol |
| `platform/` | the native Windows runner — no bash, no coreutils, no WSL |
| `notes/` | historical measurement records |
| `cases/` | curated cases for the external oracles (phase 3) |

### Not everything is differential

`zyq` answers *do the engines agree*. Three questions are not that shape and are
scripts, registered in `suites.toml` so `zyq suite` runs them anyway:

- **`fmt/`** — only one engine has a formatter, so there is nothing to compare;
  what is checked is that formatting preserves reparse, idempotence, semantics
  and comments across the whole corpus.
- **`tui/`** — `<<|` needs a real terminal. A program reading from a pipe never
  reaches raw mode, so `zyq`, which hands every engine a file descriptor,
  structurally cannot exercise it. `ptydrive.py` allocates a pty and feeds keys
  as the program asks for them. This had a README saying "the two outputs must
  be byte-identical" and nothing checking that they were.
- **`docs/`** — grades a document against the language rather than an engine
  against another, so it is reported and does not redden the gate.
- **`project/`** — a go engine, two TUI games, a neural-network library and a
  code auditor. Their suites cannot move here: each imports the application it
  tests. `apps.toml` says where they are, `run.sh` drives them through `zyq`,
  and their goldens sit beside them as Zofia's already did.

  This is the strongest regression signal the project has, and it was the
  weakest link: each application had a runner of its own that decided
  correctness by `grep -q FAIL` over the suite's output, so a suite that
  crashed half way through printed no `FAIL` and passed. Comparing against
  goldens instead found two of Zofia's programs erroring where their goldens
  record numbers, and running GO's suites on more than the tree-walker — which
  nothing had ever done — found two that zyml gets wrong.

### `bench/` is not part of the corpus

A benchmark prints elapsed wall time, so no two engines can ever agree on its
output. Keeping one in the corpus means carrying an exclusion rule to silence
it, a golden nobody can check, and a number in every report that has to be
explained away.

The twelve programs in `bench/` were in three places at once: seven benchmarks
and a stress test in `interpreter/tests/scripts/`, four more as `stress_v2/`
inside the corpus, and `lib_time.zy` — the timing module they all import — in
both. Of the four suites in the project, none of the interpreter's ran them
(they all excluded `*/scripts/*`) and zyml's skipped them by `grep -L lib_time`.
The only runner that executed them was the browser parity suite, where all ten
failed — and those ten failures were reported as divergences of the JavaScript
engine.

`interpreter/tests/scripts/run_all.sh` and `bench_gate.sh` still live with the
binary they measure and read the programs from here.

## How it decides

**Equivalence classes, not pairwise comparison.** With four engines, pairwise
gives six comparisons and no story. Grouping by answer gives it directly: one
class means agreement, and the shape of the classes names the outlier.

```
DIVERGE arith/pow_overflow.zy
    zytw                   ERROR stderr: Runtime error: power operation overflow
    zyvm                   7766279631452241920
    zyml                   -1457092405402533888
    zyjs                   100000000000000000000
```

**An answer is stdout *and* a verdict.** Comparing stdout alone cannot tell
"printed nothing and ran" from "printed nothing and refused to compile" — which
is the exact shape of the `@:label!` bug, where a label that was never declared
made one engine reject, one ignore and two do a third thing, all printing the
same empty stdout. Every pairwise suite passed it. Not the error *text*: engines
word diagnostics differently and always will (`--strict` asks for that too).

**Only engines that ran get a vote.** Missing, timed out and refusing the
program are three different things, and none of them is a wrong answer. An
engine that is not installed is reported and never counted as a pass.

**Each engine runs in a scratch directory of its own.** The `std/io` and
`std/db` tests write files; without isolation the engines race over the same
paths and the loser reports a divergence that says nothing about the language.
This was not hypothetical — it produced a false positive on the first run.

**Where the corpus sits is never part of the answer.** 47 goldens carried the
path the corpus had when they were recorded, so they passed in exactly one
checkout, on one machine, run from one directory. The corpus root is stripped
from every diagnostic before comparing.

**Three comparison modes.** `exact` is the default, because for text and
collections "close" means nothing. `numeric` compares numbers with a tolerance;
the default is **1 ULP** rather than a fixed epsilon, which is far too permissive
near zero and far too strict at 1e18. Integers are always exact — two engines
disagreeing on an integer have a bug, not a rounding difference.

## The corpus knows about itself

Every runner used to carry its own idea of which files it could not compare: a
`@vm-skip` marker, a `VM_COMPARE_EXCLUDE` regex, a 40-entry `SKIP_SET` literal
inside JavaScript, a `grep -L lib_time`, and nothing at all. None could read the
others, so a file excluded from the browser comparison because it shells out was
still counted as a divergence by zyml.

`corpus.toml` is that, once:

```toml
[[rule]]
match = "i18n/test_bash*.zy"
engines = ["zyjs"]
tag = "BASH_EXEC"
reason = "`<\\ shell \\>` has no browser equivalent"
```

The reason is **required**. An exclusion nobody wrote a reason for is
indistinguishable from a bug somebody hid. Tags let a gate drop a whole class —
`--without STD_DB` is what the release workflow used `VM_COMPARE_EXCLUDE` for.
The same file also holds the redactions (output the *network or the clock*
decided, which no engine can be right about) and the golden wildcard table.

A file in another repository declares its own rule instead, so it travels with
the file:

```zymbol
// @zyq-skip zyjs: the browser has no ODBC
```

## Adding an engine

An entry in `engines.toml`, never a patch to the runner:

```toml
[[engine]]
id = "zyrs"
cmd = ["${ZYRS_BIN:-path/to/engine}", "run", "{file}"]
check_cmd = ["path/to/engine", "check", "{file}"]   # optional
lang = "zymbol"
unsupported = ["Parse error:"]   # stderr prefixes meaning "cannot run this"
desc = "..."
```

## Current state

Measured on v0.0.9, 585 files.

**Consensus** — `./zyq consensus`:

| engines | agree | diverge |
|---|---|---|
| `zytw, zyvm` | **583** | 0 |
| all four | 480 | 103 |

Of the 103: **90 with the browser engine alone, 12 with zyml alone, 1 with
both — and none where the tree-walker or the VM is the outlier.** zyml declines
to compile 130 files, reported as *unsupported* rather than as a wrong answer.
Two files are excused for every engine: a module with no output of its own, and
`manual_check.zy`, an interactive tool that shells out and waits for a person.

That number was 117 an hour before this was written. The difference was a
duplicated JavaScript driver in this repository that skipped the static-check
pass `web/tests/run_one.mjs` already did, so a rejected program printed its
diagnostic on **stdout** and exited **0**. Deleting the duplicate and using
web's driver fixed 14 files and removed a harness nobody was maintaining.

**Goldens** — `./zyq expect`: **583 of 583 match, nothing unchecked.** That last
part is new. Five goldens used to sit in the corpus with no engine able to
produce them — four benchmarks and one file held out by a stale skip marker.
`zyq audit` reported them rather than letting them read as passes; moving the
benchmarks to `bench/` and deleting the stale marker removed the category
instead of the symptom.

**Rejections** — `./zyq reject`: **0 of 4 refused everywhere.** The browser
engine runs `m[1][2] = 77`, changes nothing and exits 0. The CLI rejects it with
five errors. A silent no-op is worse than a program that does not compile, and
no suite in the project could see it, because consensus compares what programs
print and a refused program prints nothing.

## Grading the grader

`./zyq selftest` runs 48 checks over the pattern matcher, the globs, the golden
line matcher, the skip-marker parser and the two output filters, against cases
whose answer is known by reading them. It is the first step of `zyq suite`.

The two harness defects found while producing the first consensus numbers — an
argv list reversed by a double `List.rev`, and a missing module resolver that
made every `<#` import fail — both inflated the divergence count, and neither
was visible in the output. A bench that grades 589 files has to be graded too.

## Roadmap

- **Phase 1 — consensus** ✅
- **Phase 2 — goldens, rejections, hygiene, one verdict** ✅
- **Phase 3 — oracles.** `cases/` holds a curated case plus the same computation
  in `.py` / `.js` / `.ml`, with the authoritative one declared in `case.toml`.
  This is what settles `10 ^ 20`: comparing engines against each other says
  *that* they disagree, never *who is right*, and the goldens cannot settle it
  either — they were recorded from the tree-walker, so they freeze its bugs.
- **Phase 4 — benchmarks.** `bench/` holds the programs and
  `interpreter/tests/scripts/bench_gate.sh` gates them against a per-machine
  baseline; what is missing is `zyq bench`, running Zymbol against Python,
  JavaScript and native OCaml on the same algorithm.

### `corpus/` is wide; `cases/` is deep

| | `corpus/` | `cases/` |
|---|---|---|
| Origin | the engines' test suites, merged | hand-written, curated |
| Size | 589 files, grows with each feature | small, grows slowly |
| Coverage | **wide**: touches the whole language | **deep**: hard cases |
| Authority | consensus between engines, plus goldens | external oracle |
| Cost per case | one `.zy` | one `.zy` + three implementations |

`cases/` is not a port of the corpus to Python. A case earns its place by having
revealed a divergence, by having a correct answer that is not obvious by
inspection, or by being complex enough that a small error amplifies into a
visible one. A case whose answer is obvious gains nothing from an oracle and
belongs in the corpus.

## Licence

AGPL-3.0-only, matching the rest of the project.
