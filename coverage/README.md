# coverage — what the corpus has never executed

`zyq consensus` asks whether the four engines agree. `zyq expect` asks whether
they still say what they said. Neither can ask the question this directory
asks: **what code has no test ever reached?**

That question matters because a corpus is written from what its author
understands, and what its author understands is where the bugs are not. Every
one of the 21 defects found on 2026-08-13/14 lived in a place nobody had thought
to look — integer overflow, NaN ordering, a zero divisor written as a float, a
`std/` error nobody tried to catch.

```bash
bash coverage/run.sh            # measure and report
bash coverage/run.sh --html     # also write an HTML report
bash coverage/run.sh --keep     # keep the profile, to inspect one file by hand
```

Needs `rustup component add llvm-tools-preview`. Takes a few minutes: it builds
a separate instrumented binary and runs all 594 corpus files through `run`,
`run --vm`, `check` and `fmt`.

> **It leaves `target/debug` instrumented.** An instrumented binary writes a
> `default_<hash>.profraw` into the *current directory* on every run where
> `LLVM_PROFILE_FILE` is unset — so one `cargo test` afterwards drops dozens of
> them into `interpreter/`. They are gitignored now, but the build is still
> instrumented until you rebuild:
>
> ```bash
> cd interpreter && cargo build     # plain build, no instrumentation
> ```

Deliberately **not** in `suites.toml`. It produces a list to read, not a verdict
to gate on, and a coverage percentage makes a bad gate — it rewards tests that
execute lines over tests that check answers.

## What it reports

**Coverage per file, worst first.** Four crates are excluded because no corpus
file could ever reach them and each has a suite of its own: `analyzer`/`lsp`
(driven by an editor), `repl` (interactive), `package` (`web/tests/test_zyp.mjs`),
`standalone` (`zymbol build`). Counting them would report a number nothing could
improve.

**Which bytecode instructions never ran.** The VM's dispatch loop is one match
over ~126 instructions, so an arm that never executes is a language construct no
test reaches. The script separates two cases, because they are different work:

- *GAP* — the compiler emits it, so a corpus file should run it.
- *probably DEAD* — no emission site found; confirm, then delete it.

That second label is a hint, not a verdict. There is no bytecode dump to ask,
and the compiler mentions instructions in two unrelated ways: it emits them
(`emit(…)`, `push(…)`, `Some(…)`) and it *matches* on them in register-liveness
analysis. Counting every mention called `StrSplit` emitted when the mention was
a match arm; counting only `emit(` called `Or` dead when it is emitted through
`push`. Confirm before deleting.

**Unreached lines in the VM, by kind.** Reported because the answer has been the
same every time it was asked, and it is the useful one:

| Kind | Unreached |
|---|---|
| `VmError::` | 128 |
| `raise!` | 92 |
| `TypeError` | 78 |
| `return Err` | 33 |

A corpus grows by adding programs that *work*. Error paths are where the corpus
is thinnest and, as the `CallBuiltin` bug showed — no hard `std/` error was
catchable under `--vm`, in any module — where the bugs then live.

## The first run (2026-08-14)

**60.78% of regions, 61.73% of lines**, excluding the four crates above.

24 of ~126 bytecode instructions never executed. Sorting them produced two
findings of different kinds:

- **8 string-split fusions were never exercised**: `(s $/ sep)$#`, `$>`, `$|`
  and `$<` each compile to one instruction that skips the intermediate array.
  `corpus/strings/10_split_fusion.zy` now covers the constructs — and revealed
  the second finding.
- **The fusions do not fire.** `compile_collection_length` runs, but its
  `if let Expr::StringSplit(…) = cl.collection.as_ref()` never matches, so the
  `emit(StrSplitCount(…))` line has an execution count of 0 while `StrSplit`
  has a count of 1. The optimisation is written, is reachable in principle, and
  has never once applied. Root cause not yet found — it needs the AST that
  `(s $/ ',')$#` actually produces.

The second could not have been found by writing more tests: the program is
correct either way, and only the instruction counts say the fast path is dead.
