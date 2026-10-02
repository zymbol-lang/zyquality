#!/usr/bin/env python3
"""Which diagnostics does anything actually provoke?

`extract.py` reads the source and answers *what messages exist*. This answers the
other half: *which of them has any program ever produced*. The two are different
questions and the gap between them is large — measured 2026-09-14, the engines
define 1022 diagnostics and 1281 corpus files plus 661 failing ones provoke 132.

    python3 zyquality/messages/reach.py              # the crossing, by layer
    python3 zyquality/messages/reach.py --list ejecución
    python3 zyquality/messages/reach.py --prune      # drop what is provoked now
    python3 zyquality/messages/reach.py --baseline   # deliberate, and separate

## The gate, since 2026-10-02

It was kept out of the gate because it "runs a couple of thousand processes,
minutes". Measured on 2026-10-01 it took five seconds — eight workers — and it
was red, with eleven diagnostics added since its baseline and nothing to provoke
them, while `zyq suite` said all gates pass. So it is a gate now, and its
baseline is a LIST, not a count per layer: a count that stays at 41 while one
diagnostic is reached and another is added is a green gate over a regression
(the reason ZyDDT keeps `wording.baseline` as a list).

  · a diagnostic nothing provokes that is not listed → red: give it a cell, or
    record it deliberately;
  · a listed one that something provokes now → red: `--prune` removes it, and
    can only remove, so it cannot absorb anything.

## The mistake this file exists to not repeat

The obvious crossing is to normalise both sides and compare keys. It does not
work, and it fails *quietly*: `norm` turns the source's `'{}'` into `'§'`, while
the emitted message carries the real value — `cannot reassign constant 'PI'`.
Those never match, so every templated message reads as unreached. The first
measurement of this came out at 4% and the true figure is 12%.

A template has to become a PATTERN, with its holes opened, and be matched
against what came out. That is `provoked_by` below, and it is the whole trick.

## What is out of scope, and why

Messages defined in `zymbol-cli`, `zymbol-lsp`, `zymbol-repl` and the formatter
are not reachable by running a `.zy` at all — they belong to other surfaces. They
would sit at 0% forever and say nothing, so they are counted separately and never
gated. Reporting them as debt would be filing a property of the layer as work.
"""
from __future__ import annotations

import argparse
import collections
import concurrent.futures
import os
import re
import subprocess
import sys
import tempfile

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import extract as E                                            # noqa: E402

BASELINE = os.path.join(os.path.dirname(os.path.abspath(__file__)), "reach.baseline")
ANSI = re.compile(r"\x1b\[[0-9;]*m")

# A diagnostic belongs to the layer of the crate that defines it. `harvest`
# records EVERY file a message appears in, so a message defined in two crates is
# filed under the earliest layer here — the parser's copy of a message is the
# one a user meets first.
LAYERS = (
    ("sintaxis",    {"zymbol-lexer", "zymbol-parser"}),
    ("semántica",   {"zymbol-semantic"}),
    ("ejecución",   {"zymbol-interpreter", "zymbol-vm"}),
    ("compilación", {"zymbol-compiler"}),
)
GATED = [name for name, _ in LAYERS]          # `otros` is measured, never gated


def layer_of(paths) -> str:
    crates = {p.split("crates/")[1].split("/")[0] for p in paths if "crates/" in p}
    for name, owned in LAYERS:
        if crates & owned:
            return name
    return "otros"


def is_data(text: str) -> bool:
    """A proper noun is not a diagnostic.

    `extract.py` harvests prose addressed to a reader, and the numeral-script
    table is prose by that definition: `Gunjala Gondi`, `Klingon pIqaD`. They
    would count as 22 diagnostics nobody provokes, which is true and useless.
    """
    words = text.split()
    # A capital ANYWHERE in the word, not only first: `Klingon pIqaD` is a
    # proper noun whose second word starts lower-case, and it sat in the list of
    # diagnostics nothing provokes — which nothing ever will.
    return len(words) <= 3 and all(
        any(c.isupper() for c in w) or not any(c.isalpha() for c in w) for w in words)


def provoked_by(key: str) -> re.Pattern:
    """A template, with its holes opened, as a pattern over what came out.

    `norm` has already reduced `{}` and `${…}` to `§`; each one becomes `.*?`
    and everything else is matched literally.
    """
    return re.compile("^" + ".*?".join(re.escape(p) for p in key.split("§")) + "$")


def defined() -> dict:
    """→ {key: (text, layer)} for every diagnostic the Rust engines define."""
    crates = os.path.join(E.ROOT, "interpreter", "crates")
    out = {}
    for key, (text, paths) in E.harvest(list(E.rust_files(crates)), ('"',)).items():
        if not is_data(text):
            out[key] = (text, layer_of(paths))
    return out


def _run(cmd: list[str]) -> str:
    """Run one job in a scratch directory of its own, the program by absolute path.

    It used to run each program from the program's OWN directory, so what a
    program wrote landed in the corpus, in `reject/` or among ZyDDT's generated
    cells — the defect fmt/fmt_property.sh had, which wrote `25` into this
    repository. Imports resolve from the file, not from the working directory,
    so nothing a program reads is lost by moving it."""
    try:
        with tempfile.TemporaryDirectory(prefix="reach_") as here:
            # stdin closed: a program that reads input must meet end of input,
            # not wait on the terminal this runs from until the timeout.
            r = subprocess.run(cmd, cwd=here, capture_output=True, text=True,
                               timeout=10, stdin=subprocess.DEVNULL)
        return ANSI.sub("", r.stdout + r.stderr)
    except Exception:                                          # noqa: BLE001
        return ""


DIAG = re.compile(r"\s*(?:Runtime error|error|warning)(?:\[[^\]]*\])?:\s*(.+)")
HELP = re.compile(r"\s*=?\s*help:\s*(.+)")


def one_line(text: str) -> str:
    """A diagnostic as one line of the baseline. A Rust string continued with a
    trailing `\\` keeps its newline in the harvested text, and a list whose
    entries can span two lines is a list that cannot be read back."""
    return " ".join(re.sub(r"\\\n\s*", " ", text).split())


def _no_verdict(why: str) -> None:
    """Exit 2: the question could not be asked, which is not the same as nothing
    being wrong. A SystemExit carrying a message exits 1 — a red for a harness
    that never ran — which is what these paths did at first."""
    print(f"reach: {why} — no verdict", file=sys.stderr)
    raise SystemExit(2)


def emitted(verbose: bool = True) -> set[str]:
    """Everything any of those programs actually said, lowercased.

    Two passes, because they reach different layers: `check` never runs a
    program, so it cannot produce a single execution diagnostic, and `run` on a
    corpus of programs that work produces almost none either. The second pass is
    over what is *supposed* to fail.
    """
    root = E.ROOT
    # ZyDDT's cells are generated, never committed, and this suite runs before
    # `zyddt suite` does in `zyq suite`: in a fresh clone the directory it reads
    # would be empty or stale, and the baseline — recorded WITH those cells —
    # would read as a hundred diagnostics nothing provokes. So the cells are
    # generated here first, from the declarations, every run.
    zyddt = os.path.join(root, "ZyDDT", "bin", "zyddt")
    if not os.path.exists(zyddt):
        _no_verdict("ZyDDT is not cloned beside zyquality; its cells are half of what "
                    "provokes the diagnostics")
    if subprocess.run([sys.executable, zyddt, "gen"], capture_output=True).returncode != 0:
        _no_verdict("`zyddt gen` failed")
    checked, ran = [], []
    for base in ("zyquality/corpus", "zyquality/reject", "ZyDDT/generated"):
        for d, _, fs in os.walk(os.path.join(root, base)):
            for f in fs:
                if f.endswith(".zy"):
                    checked.append(os.path.join(d, f))
    for base in ("zyquality/reject", "zyquality/corpus/errors", "ZyDDT/generated"):
        for d, _, fs in os.walk(os.path.join(root, base)):
            for f in fs:
                if f.endswith(".zy"):
                    ran.append(os.path.join(d, f))

    jobs = [["zymbol", "check", f] for f in checked]
    jobs += [["zymbol", "run", *flag, f] for f in ran for flag in ([], ["--vm"])]
    if verbose:
        print(f"  {len(checked)} ficheros con `check`, {len(ran)} con `run` "
              f"en dos motores — {len(jobs)} ejecuciones…", flush=True)

    seen: set[str] = set()
    with concurrent.futures.ThreadPoolExecutor(max_workers=8) as pool:
        for text in pool.map(_run, jobs):
            for line in text.splitlines():
                if m := DIAG.match(line):
                    seen.add(E.norm(m.group(1).strip()))
                elif m := HELP.match(line):
                    seen.add(E.norm(m.group(1).strip()))
    return seen


def cross(verbose: bool = True):
    """→ {layer: (defined, provoked, [unprovoked texts])}"""
    defs, seen = defined(), emitted(verbose)
    tally = collections.defaultdict(lambda: [0, 0, []])
    for key, (text, L) in defs.items():
        row = tally[L]
        row[0] += 1
        if any(provoked_by(key).match(s) for s in seen):
            row[1] += 1
        else:
            row[2].append(text)
    return tally


HEADER = ("# Diagnostics nothing provokes, one per line: layer TAB text. A list and\n"
          "# not a count, so one reached cannot hide one added. A diagnostic missing\n"
          "# from here that nothing provokes is red, and so is one listed here that\n"
          "# something provokes now — remove those with `reach.py --prune`, which\n"
          "# only removes. `--baseline` rewrites the whole file: deliberate, and\n"
          "# separate, like messages/baseline.txt.\n")


def read_baseline() -> set[tuple[str, str]] | None:
    if not os.path.exists(BASELINE):
        return None
    out = set()
    for line in open(BASELINE, encoding="utf-8"):
        line = line.rstrip("\n")
        if line and not line.startswith("#"):
            if "\t" not in line:
                # The count format of 2026-09-14. Refused, not converted: turning
                # "sintaxis 41" into a list would mean choosing which 41.
                _no_verdict(f"{BASELINE} is in the old count format; record a list "
                            f"with --baseline")
            layer, text = line.split("\t", 1)
            out.add((layer, text))
    return out


def write_baseline(rows: set[tuple[str, str]]) -> None:
    with open(BASELINE, "w", encoding="utf-8") as fh:
        fh.write(HEADER)
        for layer, text in sorted(rows):
            fh.write(f"{layer}\t{text}\n")


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--list", metavar="CAPA",
                    help="print the diagnostics of one layer that nothing provokes")
    ap.add_argument("--baseline", action="store_true",
                    help="record today's list; deliberate and separate")
    ap.add_argument("--prune", action="store_true",
                    help="remove listed diagnostics something provokes now; only removes")
    args = ap.parse_args()

    tally = cross(verbose=not args.list)

    if args.list:
        rows = tally.get(args.list)
        if not rows:
            print(f"reach: no such layer: {args.list}\n"
                  f"       one of: {', '.join(GATED)}, otros", file=sys.stderr)
            return 2
        for text in sorted(one_line(x) for x in rows[2]):
            print(text)
        return 0

    print(f"\n  {'capa':<13}{'definidos':>11}{'provocados':>12}{'sin provocar':>14}{'%':>6}")
    total = [0, 0]
    for L in (*GATED, "otros"):
        d, p, _ = tally[L]
        if L != "otros":
            total[0] += d
            total[1] += p
        mark = "  (fuera de alcance)" if L == "otros" else ""
        print(f"  {L:<13}{d:>11}{p:>12}{d - p:>14}{100 * p // max(d, 1):>5}%{mark}")
    print(f"  {'gated':<13}{total[0]:>11}{total[1]:>12}{total[0] - total[1]:>14}"
          f"{100 * total[1] // max(total[0], 1):>5}%")

    now = {(L, one_line(text)) for L in GATED for text in tally[L][2]}
    if args.baseline:
        write_baseline(now)
        print(f"\n  línea base escrita: {len(now)} diagnóstico(s) sin provocar")
        return 0

    base = read_baseline()
    if base is None:
        print("\n  sin línea base — `--baseline` para grabar la de hoy")
        return 2

    stale = sorted(base - now)          # provoked now, or no longer defined
    if args.prune:
        write_baseline(base - set(stale))
        print(f"\n  línea base podada: {len(stale)} quitado(s), {len(base) - len(stale)} quedan")
        return 0

    new = sorted(now - base)
    rc = 0
    if new:
        print(f"\n  ✗ {len(new)} diagnóstico(s) que nada provoca y la línea base no lista "
              f"— dales una celda:")
        for L, text in new:
            print(f"      {L:<12} {text[:90]}")
        rc = 1
    if stale:
        print(f"\n  ✗ {len(stale)} diagnóstico(s) de la línea base que ya se provocan, "
              f"o ya no existen — `--prune` los quita:")
        for L, text in stale[:12]:
            print(f"      {L:<12} {text[:90]}")
        if len(stale) > 12:
            print(f"      … y {len(stale) - 12} más")
        rc = 1
    if rc == 0:
        print(f"\n  ✓ nada nuevo sin provocar ({len(base)} en la línea base)")
    return rc


if __name__ == "__main__":
    sys.exit(main())
