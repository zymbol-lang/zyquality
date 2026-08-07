<p align="center">
  <img src="logo.png" alt="Zymbol-Lang" width="180"/>
</p>

<h1 align="center">ZyQuality</h1>

<p align="center">
  Differential test bench for the Zymbol engines.<br/>
  Runs one program through every engine and asks whether they agree.
</p>

<p align="center">
  <img src="https://img.shields.io/badge/version-v0.1.0-informational?style=flat-square"/>
  <img src="https://img.shields.io/badge/language-OCaml-e88b00?style=flat-square"/>
  <img src="https://img.shields.io/badge/license-AGPL--3.0-blue?style=flat-square"/>
  <img src="https://img.shields.io/badge/status-experimental-yellow?style=flat-square"/>
  <img src="https://img.shields.io/badge/corpus-549%20files-brightgreen?style=flat-square"/>
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
would accept without complaint. The existing gate cannot see this, for two
reasons:

1. **`vm_compare.sh` compares two engines**, tree-walker against VM. A
   disagreement that involves the JavaScript engine or `zyml` is invisible to
   it.
2. **There is no external authority.** Comparing engines against each other
   says *that* they disagree, never *who is right*. The corpus `.expected`
   files cannot settle it either: they were generated from the tree-walker, so
   they freeze its bugs — the one for `"héllo"#?` says 6, and 5 is correct.

ZyQuality answers both: it runs N engines **and**, for curated cases, the same
computation written in Python, JavaScript and OCaml — which are an authority
precisely because they do not depend on any Zymbol implementation being right.
Timing all of that also gives Zymbol's cost against those languages.

## Quick start

```bash
make
./zyq engines                        # what is installed, what is not
./zyq consensus                      # the corpus through every Zymbol engine
./zyq consensus --engines zytw,zyvm  # what vm_compare.sh checks today
./zyq show corpus/path/to/case.zy    # what each engine said about one file
./zyq consensus --json               # for CI
```

No dune, no opam switch, no external libraries — `ocamlopt` and `unix`, the
same as [zyml](../zyml).

## How it decides

**Equivalence classes, not pairwise comparison.** With four engines, pairwise
gives six comparisons and no story. Grouping by output gives the answer
directly: one class means agreement, and the shape of the classes names the
outlier.

```
DIVERGE corpus/arith/pow_overflow.zy
    zytw                   stderr: Runtime error: power operation overflow: 10^20
    zyvm                   7766279631452241920
    zyml                   -1457092405402533888
    zyjs                   100000000000000000000
```

**Only engines that ran get a vote.** Missing, timed out or refusing the
program are three different things, and none of them is a wrong answer. An
engine that is not installed is reported and never counted as a pass — a gate
must not read "nothing ran" as "nothing failed".

**Each engine runs in a scratch directory of its own.** The `std/io` and
`std/db` tests write files; without isolation the engines race over the same
paths and the loser reports a divergence that says nothing about the language.
This was not hypothetical — it produced a false positive on the first run.

**Three comparison modes.** `exact` is the default, because for text and
collections "close" means nothing. `numeric` compares numbers with a tolerance
and everything between them exactly; the default tolerance is **1 ULP** rather
than a fixed epsilon, which is far too permissive near zero and far too strict
at 1e18. Integers are always exact — two engines disagreeing on an integer have
a bug, not a rounding difference.

## Adding an engine

An entry in `engines.toml`, never a patch to the runner:

```toml
[[engine]]
id = "zyrs"
cmd = ["path/to/engine", "run", "{file}"]
lang = "zymbol"
unsupported = ["Parse error:"]   # stderr prefixes meaning "cannot run this"
desc = "..."
```

## Current state

`./zyq consensus` over the 549-file corpus:

| engines | agree | diverge |
|---|---|---|
| `zytw, zyvm` | **549** | 0 |
| `zytw, zyvm, zyml` | 538 | 11 |
| all four | 413 | 136 |

The tree-walker and the VM agree on everything, which is what `vm_compare.sh`
already told us and confirms this runner is equivalent to it. The interesting
column is the last one.

`zyml` is the sole outlier on 9 files and declines to compile 191 — it does not
implement `std/*` yet, which is reported as *unsupported*, not as a wrong
answer.

**`zyjs` is the sole outlier on 129 of 549 files**, and that number needs
qualifying before anyone acts on it. A first pass shows 56 are the JavaScript
engine emitting `warning:` on stdout where the Rust engines use stderr — a
channel difference, not a semantic one — and a handful are TUI escape sequences
it does not emit. Characterising the rest is the next piece of work, and until
it is done the honest statement is "129 differences, most of them probably not
bugs", not "129 bugs".

Two harness defects were found and fixed while producing that number, both of
which had inflated it: an argv list reversed by a double `List.rev`, and a
missing `moduleResolver` that made every `<#` import fail under `zyjs`.

## Roadmap

- **Phase 1 — consensus** ✅ what you see here.
- **Phase 2 — oracles.** `cases/` holds a curated case plus the same
  computation in `.py` / `.js` / `.ml`, with the authoritative one declared in
  `case.toml`. This is what settles `10 ^ 20`.
- **Phase 3 — benchmarks.** Zymbol against Python, JavaScript and native OCaml
  on the same algorithm.
- **Phase 4 — reconnection.** `vm_compare.sh` becomes a thin wrapper over
  `zyq consensus --engines zytw,zyvm`, keeping its interface.

### `corpus/` is wide; `cases/` is deep

|  | `corpus/` | `cases/` |
|---|---|---|
| Origin | the Zymbol interpreter's test suite | hand-written, curated |
| Size | 549 files, grows with each feature | small, grows slowly |
| Coverage | **wide**: touches the whole language | **deep**: hard cases |
| Authority | consensus between engines | external oracle |
| Cost per case | one `.zy` | one `.zy` + three implementations |

`cases/` is not a port of the corpus to Python. A case earns its place by
having revealed a divergence, by having a correct answer that is not obvious
by inspection, or by being complex enough that a small error amplifies into a
visible one. A case whose answer is obvious gains nothing from an oracle and
belongs in the corpus.

## Licence

AGPL-3.0-only, matching the rest of the project.
