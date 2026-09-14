#!/usr/bin/env python3
"""Which diagnostics does anything actually provoke?

`extract.py` reads the source and answers *what messages exist*. This answers the
other half: *which of them has any program ever produced*. The two are different
questions and the gap between them is large — measured 2026-09-14, the engines
define 1022 diagnostics and 1281 corpus files plus 661 failing ones provoke 132.

    python3 zyquality/messages/reach.py              # the crossing, by layer
    python3 zyquality/messages/reach.py --list ejecución
    python3 zyquality/messages/reach.py --baseline   # deliberate, and separate

## Why this is not in the gate

It runs the corpus twice over — `check` on everything, `run` on everything that
should fail, in both Rust engines — which is a couple of thousand processes. The
precedent is `coverage/`, carried over from the same reasoning and deliberately
outside the gate. What IS in the gate is the baseline: the count may only go
down, so a diagnostic added with nothing to provoke it shows up the day it is
written rather than at the next manual sweep.

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
    return len(words) <= 3 and all(
        w[:1].isupper() or not w[:1].isalpha() for w in words)


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


def _run(cmd: list[str], cwd: str) -> str:
    try:
        r = subprocess.run(cmd, cwd=cwd, capture_output=True, text=True, timeout=10)
        return ANSI.sub("", r.stdout + r.stderr)
    except Exception:                                          # noqa: BLE001
        return ""


DIAG = re.compile(r"\s*(?:Runtime error|error|warning)(?:\[[^\]]*\])?:\s*(.+)")
HELP = re.compile(r"\s*=?\s*help:\s*(.+)")


def emitted(verbose: bool = True) -> set[str]:
    """Everything any of those programs actually said, lowercased.

    Two passes, because they reach different layers: `check` never runs a
    program, so it cannot produce a single execution diagnostic, and `run` on a
    corpus of programs that work produces almost none either. The second pass is
    over what is *supposed* to fail.
    """
    root = E.ROOT
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

    jobs = [(["zymbol", "check", os.path.basename(f)], os.path.dirname(f))
            for f in checked]
    jobs += [(["zymbol", "run", *flag, os.path.basename(f)], os.path.dirname(f))
             for f in ran for flag in ([], ["--vm"])]
    if verbose:
        print(f"  {len(checked)} ficheros con `check`, {len(ran)} con `run` "
              f"en dos motores — {len(jobs)} ejecuciones…", flush=True)

    seen: set[str] = set()
    with concurrent.futures.ThreadPoolExecutor(max_workers=8) as pool:
        for text in pool.map(lambda j: _run(*j), jobs):
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


def read_baseline() -> dict | None:
    if not os.path.exists(BASELINE):
        return None
    out = {}
    for line in open(BASELINE, encoding="utf-8"):
        line = line.strip()
        if line and not line.startswith("#"):
            name, n = line.rsplit(None, 1)
            out[name] = int(n)
    return out


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--list", metavar="CAPA",
                    help="print the diagnostics of one layer that nothing provokes")
    ap.add_argument("--baseline", action="store_true",
                    help="record today's counts; deliberate and separate")
    args = ap.parse_args()

    tally = cross(verbose=not args.list)

    if args.list:
        rows = tally.get(args.list)
        if not rows:
            print(f"reach: no such layer: {args.list}\n"
                  f"       one of: {', '.join(GATED)}, otros", file=sys.stderr)
            return 2
        for text in sorted(rows[2]):
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

    if args.baseline:
        with open(BASELINE, "w", encoding="utf-8") as fh:
            fh.write("# Diagnostics nothing provokes, by layer. The number may only\n"
                     "# go DOWN: one that goes up means a message was added with\n"
                     "# nothing to reach it, which is the day to notice rather than\n"
                     "# at the next manual sweep. Recorded by `reach.py --baseline`,\n"
                     "# deliberately and separately, like messages/baseline.txt.\n")
            for L in GATED:
                d, p, _ = tally[L]
                fh.write(f"{L} {d - p}\n")
        print(f"\n  línea base escrita: {BASELINE}")
        return 0

    base = read_baseline()
    if base is None:
        print("\n  sin línea base — `--baseline` para grabar la de hoy")
        return 0

    worse = [(L, tally[L][0] - tally[L][1], base[L])
             for L in GATED if L in base and tally[L][0] - tally[L][1] > base[L]]
    if worse:
        print()
        for L, now, was in worse:
            print(f"  ✗ {L}: {now} sin provocar, la línea base dice {was} "
                  f"— {now - was} diagnóstico(s) nuevo(s) que nada alcanza")
        return 1

    better = [(L, tally[L][0] - tally[L][1], base[L])
              for L in GATED if L in base and tally[L][0] - tally[L][1] < base[L]]
    if better:
        print()
        for L, now, was in better:
            print(f"  ↑ {L}: {was} → {now} — regraba la línea base para fijarlo")
    else:
        print("\n  ✓ nada nuevo sin provocar")
    return 0


if __name__ == "__main__":
    sys.exit(main())
