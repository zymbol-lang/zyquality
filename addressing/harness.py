#!/usr/bin/env python3
"""addressing/harness.py — the bracket rule, crossed rather than listed.

`arr[i][j]` is refused; `arr[i>j]` is the form.  `reject/collections/13`, `14`
and `15` hold three points of that rule down, and `corpus/collections/
frontera_corchete.zy` holds the legal boundary.  All four are files somebody
wrote, so between them they cover the actions somebody thought of.

This harness crosses instead.  The rule is about **how an element is addressed**,
and any action in the language can be written after the address, so the coverage
question is a product and not a list:

    receiver   {chained, navigator}  ×  action  {read, bind, edit, build, …}

and the claim is one line: every chained cell must be refused by every engine,
every navigator cell must be accepted and agreed on by every engine.

── Why this exists next to `reject/` and not inside it ──────────────────────

Because the hole this closes was found the hard way.  When the read was closed
on 2026-09-06 the first cut carved out an exception for `$~`, so a sibling
refusal could keep its older wording — and the exception let through exactly the
two actions that have somewhere to put their result:

    arr[1][1] $~ 0          →  ran, printed [[0,2,3],[4,5,6],[7,8,9]]
    x = arr[1][1] $~ 0      →  ran, x = [0, 2, 3]

Both in all three engines, exit 0, no diagnostic.  A consensus run cannot see
that: three engines that wrongly accept the same program agree perfectly.  A
hand-written `reject/` file cannot see it either, unless the hand that wrote it
had thought of `$~` — and the hand that carved the exception was the same one.

The product can.  It does not need anyone to think of `$^+` after a chained
receiver: it is a point, so it is asked.

── What it does not do ─────────────────────────────────────────────────────

It does not compare messages — `messages/` owns that — and it does not record
goldens, because the values are already held by `corpus/collections/
frontera_corchete.zy`.  It asks two questions only: was it refused, and did the
engines agree.

Exit status: 0 every cell holds, 1 one does not, 2 could not run.
"""
from __future__ import annotations

import os
import subprocess
import sys
import tempfile
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parent

# The engines, spelled as `engines.toml` spells them. Read from there rather
# than repeated, so an engine added to the project is asked here too.
def engines() -> list[tuple[str, list[str]]]:
    """(id, argv-with-{file}) for every Zymbol engine `engines.toml` declares."""
    out, cur = [], {}
    for raw in (ROOT / "engines.toml").read_text(encoding="utf-8").splitlines():
        line = raw.strip()
        if line.startswith("[[engine]]"):
            if cur.get("lang") == "zymbol" and "cmd" in cur:
                out.append((cur["id"], cur["cmd"]))
            cur = {}
        elif line.startswith("id ="):
            cur["id"] = line.split("=", 1)[1].strip().strip('"')
        elif line.startswith("lang ="):
            cur["lang"] = line.split("=", 1)[1].strip().strip('"')
        elif line.startswith("cmd ="):
            raw_cmd = line.split("=", 1)[1].strip()
            cur["cmd"] = [p.strip().strip('"') for p in
                          raw_cmd.strip("[]").split(",") if p.strip()]
    if cur.get("lang") == "zymbol" and "cmd" in cur:
        out.append((cur["id"], cur["cmd"]))
    return out


def expand(argv: list[str], f: Path) -> list[str]:
    """`${NAME:-default}` from the environment, `{file}` from the case."""
    out = []
    for a in argv:
        if a.startswith("${") and a.endswith("}"):
            body = a[2:-1]
            name, _, default = body.partition(":-")
            a = os.environ.get(name, default)
        out.append(a.replace("{file}", str(f)))
    return out


# ── The matrix ───────────────────────────────────────────────────────────────
#
# `«recv»` is the only thing that varies between the two halves of a row, so a
# cell that is refused in one half and accepted in the other differs by the
# notation and by nothing else. That is what makes the row an experiment rather
# than two tests.

# Two shapes, because half the action vocabulary needs a collection to act on.
# `arr[1][1]` and `arr[1>1]` both address a scalar, so `$+` after either of them
# is refused for a reason that has nothing to do with brackets — pairing them
# that way made five rows red on the first run and each red was the harness
# asking a nonsense question. A cell must fail for the reason it is about.
SHAPES = {
    # what the receiver lands on:  scalar             collection
    "scalar":     ("arr = [[1,2,3],[4,5,6],[7,8,9]]", "arr[1][1]", "arr[1>1]"),
    "collection": ("arr = [[[1,2],[3,4]],[[5,6],[7,8]]]", "arr[1][1]", "arr[1>1]"),
}

# Each action names the shape it needs. `«recv»` is the ONLY thing that differs
# between the two halves of a row, so a row that is refused in one half and
# accepted in the other differs by the notation and by nothing else — which is
# what makes it an experiment rather than two tests.
ACTIONS = [
    ("read",      "scalar",     ">> «recv» ¶"),
    ("bind",      "scalar",     "x = «recv»\n>> x ¶"),
    ("edit",      "scalar",     "«recv» $~ 0\n>> arr ¶"),
    ("build",     "scalar",     "x = «recv» $~ 0\n>> x ¶"),
    ("argument",  "scalar",     "f(v) { <~ v }\n>> f(«recv») ¶"),
    ("condition", "scalar",     "? «recv» == 1 { >> \"si\" ¶ }"),
    ("append",    "collection", "«recv» $+ 5\n>> arr ¶"),
    ("remove",    "collection", "«recv» $- 1\n>> arr ¶"),
    ("sort",      "collection", "«recv» $^+\n>> arr ¶"),
    ("length",    "collection", ">> «recv» $# ¶"),
    ("contains",  "collection", ">> «recv» $? 1 ¶"),
    ("slice",     "collection", ">> «recv» $[1..2] ¶"),
]


def cells():
    """(id, source, must_be_refused) for every point of the product."""
    for name, shape, body in ACTIONS:
        prelude, chained, navigator = SHAPES[shape]
        for half, recv, refused in (("chained", chained, True),
                                    ("navigator", navigator, False)):
            src = prelude + "\n" + body.replace("«recv»", recv) + "\n"
            yield f"{half}-{name}", src, refused


def run(argv: list[str], src: str) -> tuple[int, str]:
    with tempfile.TemporaryDirectory() as d:
        f = Path(d) / "case.zy"
        f.write_text(src, encoding="utf-8")
        try:
            p = subprocess.run(expand(argv, f), capture_output=True,
                               text=True, timeout=30, stdin=subprocess.DEVNULL)
        except FileNotFoundError:
            return -1, ""
        except subprocess.TimeoutExpired:
            return -2, ""
        # The exit code does not classify on its own: `<~ n` is the status the
        # program chooses. A refusal is a diagnostic on stderr, so that is what
        # is read. (ZyDDT's first trap, VERDICTS § 1.)
        refused = "error" in p.stderr
        return (1 if refused else 0), p.stdout


def main() -> int:
    engs = engines()
    missing = [e for e, argv in engs if run(argv, ">> 1 ¶\n")[0] == -1]
    if missing:
        print(f"addressing: engine(s) not runnable: {', '.join(missing)}",
              file=sys.stderr)
        return 2                      # absent layer is 2, never "nothing failed"

    verbose = "-v" in sys.argv
    accepted, diverged, ok = [], [], 0

    for cid, src, must_refuse in cells():
        answers = {}
        for eid, argv in engs:
            rc, out = run(argv, src)
            answers[eid] = (rc, out)

        if must_refuse:
            ran = [e for e, (rc, _) in answers.items() if rc == 0]
            if ran:
                accepted.append((cid, ran, src))
            else:
                ok += 1
        else:
            refusers = [e for e, (rc, _) in answers.items() if rc != 0]
            outs = {o for _, o in answers.values()}
            if refusers:
                accepted.append((cid, [f"refused by {','.join(refusers)}"], src))
            elif len(outs) > 1:
                diverged.append((cid, answers, src))
            else:
                ok += 1
        if verbose and not accepted and not diverged:
            print(f"  ok   {cid}")

    total = ok + len(accepted) + len(diverged)
    for cid, who, src in accepted:
        print(f"  \033[0;31mFAIL\033[0m {cid}: {', '.join(who)}")
        for line in src.strip().splitlines():
            print(f"       | {line}")
    for cid, answers, src in diverged:
        print(f"  \033[0;31mDIVERGE\033[0m {cid}")
        for e, (_, out) in answers.items():
            print(f"       {e:<6} {out.strip()!r}")

    bad = len(accepted) + len(diverged)
    print(f"\n  addressing  {total} cells: \033[0;32m{ok}\033[0m hold, "
          + (f"\033[0;31m{bad}\033[0m do not" if bad else "\033[0;32m0\033[0m do not"))
    print("  every chained receiver refused by every engine; "
          "every navigator receiver accepted and agreed")
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main())
