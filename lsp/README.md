# `lsp/` — the editor's answer against the command line's

`zymbol check` and the language server are meant to run the same analysis on
the same file. Nothing compared them, so when they disagreed the only symptom
was a red squiggle over a program that ran perfectly — and no way to tell
whether the editor was wrong, the CLI was wrong, or neither.

```bash
python3 lsp/lsp_parity.py                # the corpus
python3 lsp/lsp_parity.py corpus/i18n    # a subtree
python3 lsp/lsp_parity.py --keep-open    # every document open, as an editor has them
python3 lsp/lsp_parity.py -v             # list the disagreements the baseline knows
./zyq suite --only lsp                   # the same thing, through the gate
```

## Read this before filing a bug

**A language server is a process, and replacing its binary does not replace the
process.** Every `cargo build --release` writes a new `zymbol-lsp` while the
editor keeps running the one it started with — the old inode stays alive as
long as the process holds it. An editor opened before a release therefore
reports the *previous* release's rules, which looks exactly like a regression
and is not one.

Measured on 2026-08-20, with a server binary six days old against the corpus of
that day: **47 files flagged that run correctly**, every message a v0.0.9
collections rule the old server had never heard of —

| what the stale server said | what it had not learnt |
|---|---|
| `expected ')' after function arguments` | `f(x<~)`, the call-site output mark (L36) |
| `array index must be Int, got String` | `d["k"]`, the dictionary's computed key |
| `expected '=' after index expression…` | `arr[i]$~ v`, the rule of the result |
| `argument N has type String, expects Int` | a parameter used as a dictionary key (L42) |
| `unexpected '[' at statement level` | `#[…]` |
| `expected '{' to start block` | `@ (k, v):d` |

The same run against the current binary: **0 unexplained**. So the procedure is
— run this suite. Clean here while the editor is not means restart the editor's
server, and nothing is wrong with the code.

## `baseline.txt`

Eighteen disagreements are correct and are listed there with the reason. They
are all one case: the LSP **resolves the file's imports from disk** and reports
what it finds, because an editor has the whole project in front of it and a
command line has one file. On a fixture whose whole point is a bad import —
circular, private, missing — the LSP speaks and the CLI does not, and the LSP
is right.

A file in that list that is not an import fixture is a defect in one of the two.
