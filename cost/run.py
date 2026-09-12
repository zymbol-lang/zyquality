#!/usr/bin/env python3
"""The cost gate — ratios, never numbers.

Two questions no other suite in this repository can ask:

  · does auto-free still release a value after its last use?  It is required to
    be INVISIBLE — a correct program prints the same thing with and without it —
    so the only observable is the high-water mark of memory, and the only way to
    see that is against a control whose values may not be released.

  · did something change COMPLEXITY?  `bench/` runs each program at one size and
    compares milliseconds to a machine-specific baseline, so a change from
    linear to quadratic looks like "slower" until the input grows and it looks
    like a hang.  Measuring the same program at N and 4N answers it directly.

Every case carries its own control, measured in the same run on the same
machine.  What is asserted is the ratio, so there is no baseline to re-record —
and re-recording a baseline is how a regression gets absorbed.

Exit: 0 green, 1 red, 2 no verdict (an engine could not be measured).
"""
from __future__ import annotations

import os
import statistics
import sys
import time
import tomllib
from pathlib import Path

ROOT = Path(__file__).resolve().parent
GREEN, RED, NOVERDICT = 0, 1, 2

ZYMBOL = os.environ.get("ZYMBOL_BIN", "zymbol")
ZYJS = os.environ.get("ZYJS_RUNNER", str(ROOT.parents[1] / "web/tests/run_one.mjs"))

class TooFast(RuntimeError):
    """The base run is too short for its ratio to mean anything."""


ENGINES = {
    "zytw": lambda f: [ZYMBOL, "run", str(f)],
    "zyvm": lambda f: [ZYMBOL, "run", "--vm", str(f)],
    "zyjs": lambda f: ["node", ZYJS, str(f)],
}

C = {"red": "\033[31m", "green": "\033[32m", "yellow": "\033[33m",
     "dim": "\033[2m", "bold": "\033[1m", "off": "\033[0m"}
if not sys.stdout.isatty():
    C = dict.fromkeys(C, "")


def measure(cmd: list[str], cwd: Path) -> tuple[float, float, int]:
    """→ (peak RSS in MB, wall seconds, exit status) for ONE child.

    `os.wait4` rather than `resource.getrusage(RUSAGE_CHILDREN)`: the latter is
    the maximum over every child the process has ever reaped, so the second
    measurement in a run would inherit the first one's peak and every case after
    the largest would silently report that one instead of itself.
    """
    t0 = time.monotonic()
    pid = os.fork()
    if pid == 0:                                  # child
        try:
            os.chdir(cwd)
            # stdin too, and it is not decoration: a measured program that
            # reaches `<<` would otherwise inherit the terminal and block
            # forever, and a harness that hangs is worse than one that fails.
            os.dup2(os.open(os.devnull, os.O_RDONLY), 0)
            null = os.open(os.devnull, os.O_WRONLY)
            os.dup2(null, 1)
            os.dup2(null, 2)
            os.execvp(cmd[0], cmd)
        except Exception:
            pass
        os._exit(127)
    _, status, ru = os.wait4(pid, 0)
    return ru.ru_maxrss / 1024.0, time.monotonic() - t0, status


def median_time(cmd, cwd, runs) -> tuple[float, int]:
    out = [measure(cmd, cwd) for _ in range(runs)]
    bad = next((s for _, _, s in out if s != 0), 0)
    return statistics.median(t for _, t, _ in out), bad


def render(template: Path, n: int) -> Path:
    """Write the template at one size, beside it so its imports still resolve."""
    dst = template.with_suffix("")          # x.zy.in → x.zy
    dst = dst.with_name(f"_n{n}_{dst.name}")
    dst.write_text(template.read_text(encoding="utf-8").replace("«N»", str(n)),
                   encoding="utf-8")
    return dst


def off_file(fid: str) -> str:
    """→ the HALLAZGOS file a finding id belongs to, by its prefix."""
    return {"ZYTW": "zytw.md", "ZYVM": "zyvm.md", "ZYJS": "zyjs.md"}.get(
        fid.split("-")[0], "GLOBAL.md")


def main() -> int:
    doc = tomllib.loads((ROOT / "cost.toml").read_text(encoding="utf-8"))
    defaults = doc.get("defaults", {})
    rc, tmp = GREEN, []

    print(f"{C['bold']}  Cost gate — ratios measured against their own control{C['off']}")
    print(f"{C['dim']}  no baseline: every limit is a ratio declared in cost.toml{C['off']}\n")

    for case in doc["case"]:
        kind, cid = case["kind"], case["id"]
        limit = case["max_ratio"]
        print(f"  {C['bold']}{cid}{C['off']}  {C['dim']}{case['what']}{C['off']}")
        for eng in case.get("engines", defaults.get("engines", [])):
            if eng not in ENGINES:
                print(f"    {C['yellow']}NO VERDICT{C['off']}  unknown engine {eng!r}")
                rc = max(rc, NOVERDICT)
                continue
            try:
                if kind == "peak-ratio":
                    s, ss = measure(ENGINES[eng](ROOT / case["subject"]), ROOT)[0::2]
                    c, cs = measure(ENGINES[eng](ROOT / case["control"]), ROOT)[0::2]
                    if ss or cs:
                        raise RuntimeError(f"engine exited {ss or cs}")
                    ratio, unit = s / c, f"{s:.0f}MB vs {c:.0f}MB"
                else:
                    tpl = ROOT / case["template"]
                    n = case.get("n_by_engine", {}).get(eng, case["n"])
                    f = case["factor"]
                    a, b = render(tpl, n), render(tpl, n * f)
                    tmp += [a, b]
                    runs = defaults.get("runs_time", 3)
                    ta, bad_a = median_time(ENGINES[eng](a), ROOT, runs)
                    tb, bad_b = median_time(ENGINES[eng](b), ROOT, runs)
                    if bad_a or bad_b:
                        raise RuntimeError(f"engine exited {bad_a or bad_b}")
                    floor = defaults.get("min_base_ms", 0) / 1000.0
                    if ta < floor:
                        raise TooFast(f"base run {ta*1000:.0f}ms < "
                                      f"{floor*1000:.0f}ms floor — this ratio "
                                      f"would measure process startup")
                    ratio = tb / ta if ta else float("inf")
                    unit = f"{ta*1000:.0f}ms→{tb*1000:.0f}ms at ×{f}"
            except Exception as e:                      # noqa: BLE001
                print(f"    {C['yellow']}NO VERDICT{C['off']}  {eng:5s}  {e}")
                rc = max(rc, NOVERDICT)
                continue

            ok = ratio <= limit
            known = case.get("open_finding", {}).get(eng)
            if ok:
                tag = f"{C['green']}PASS{C['off']}"
            elif known:
                tag = f"{C['yellow']}KNOWN{C['off']}"
            else:
                tag = f"{C['red']}FAIL{C['off']}"
            print(f"    {tag}  {eng:5s}  ratio {ratio:5.2f}  limit {limit:4.2f}   "
                  f"{C['dim']}{unit}{C['off']}")
            if not ok:
                print(f"          {C['dim']}{case['why']}{C['off']}")
                if known:
                    # Declared debt, not a regression: reported every run, with
                    # its id, and not counted against the gate.
                    print(f"          {C['dim']}declared: {known} — "
                          f"ZyDDT/HALLAZGOS/{off_file(known)}{C['off']}")
                else:
                    rc = RED if rc != NOVERDICT else rc
            elif known:
                # The other direction, which is the one nobody builds: debt that
                # got fixed and whose marker stayed behind.
                print(f"          {C['green']}{known} now passes — close the "
                      f"finding and drop `open_finding`{C['off']}")
        print()

    for f in tmp:
        f.unlink(missing_ok=True)

    if rc == GREEN:
        print(f"  {C['green']}{C['bold']}GREEN{C['off']} — every ratio within its declared limit")
    elif rc == RED:
        print(f"  {C['red']}{C['bold']}RED{C['off']} — a declared cost ratio was exceeded")
    else:
        print(f"  {C['yellow']}{C['bold']}NO VERDICT{C['off']} — something could not be measured")
    return rc


if __name__ == "__main__":
    sys.exit(main())
