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
import re
import statistics
import subprocess
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
    "zytw": lambda f: [ZYMBOL, "run", "--tw", str(f)],
    "zyvm": lambda f: [ZYMBOL, "run", "--vm", str(f)],
    "zyjs": lambda f: ["node", ZYJS, str(f)],
}

# The engines `zymbol run --count` exists for. zyjs has no counters, so the
# clock is the only instrument it can be asked with.
COUNTING = ("zytw", "zyvm")

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


COUNT_LINE = re.compile(r"^count  (.+)$", re.MULTILINE)


def counted(cmd: list[str], cwd: Path) -> dict[str, int]:
    """→ the five counters `zymbol run --count` prints, for ONE run.

    Exact: the same program gives the same numbers on every run, on every
    machine, whatever else the machine is doing. So one run is enough, there is
    no floor below which the answer is noise, and the limit can sit just above
    the true ratio instead of half way to the next complexity class.
    """
    cmd = cmd[:2] + ["--count"] + cmd[2:]             # zymbol run --count [--vm] FILE
    r = subprocess.run(cmd, cwd=cwd, capture_output=True, text=True,
                       stdin=subprocess.DEVNULL, timeout=300)
    m = COUNT_LINE.search(r.stderr)
    if r.returncode != 0 or not m:
        raise RuntimeError(f"engine exited {r.returncode}"
                           + ("" if m else " and printed no `count` line"))
    return {k: int(v) for k, v in (pair.split("=") for pair in m.group(1).split())}


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
    rc, tmp, skipped = GREEN, [], 0

    print(f"{C['bold']}  Cost gate — ratios measured against their own control{C['off']}")
    print(f"{C['dim']}  no baseline: every limit is a ratio declared in cost.toml{C['off']}\n")

    for case in doc["case"]:
        kind, cid = case["kind"], case["id"]
        limit = case["max_ratio"]
        # A growth case is also asked in `--count`'s units (the end of this
        # body), unless it opted out. Known up front because it decides what a
        # timed ratio under the floor means: see `too_fast`.
        limits = {**defaults.get("count", {}), **case.get("count", {})}
        counted_here = kind == "growth-ratio" and bool(limits) and not case.get("count_off")
        # engine → why the clock refused to answer. Only for an engine that is
        # ALSO counted: the counted ratios are exact and have no floor, so the
        # case is answered there, and the line saying so is printed with them,
        # where it is known whether they passed. An engine the counters do not
        # reach (zyjs, a `count_off` case, a `time-ratio`) keeps NO VERDICT: the
        # clock is the only thing that could have answered it.
        too_fast: dict[str, str] = {}
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
                elif kind == "time-ratio":
                    # Subject against control at ONE size, wall time: the same
                    # work written two ways, so the ratio is what the difference
                    # between them costs (a function call in the hot loop, for
                    # IDEA-GOL-007) — on this machine, against itself.
                    n = case.get("n_by_engine", {}).get(eng, case["n"])
                    sf, cf = render(ROOT / case["subject"], n), render(ROOT / case["control"], n)
                    tmp += [sf, cf]
                    runs = defaults.get("runs_time", 3)
                    ts, bad_s = median_time(ENGINES[eng](sf), ROOT, runs)
                    tc, bad_c = median_time(ENGINES[eng](cf), ROOT, runs)
                    if bad_s or bad_c:
                        raise RuntimeError(f"engine exited {bad_s or bad_c}")
                    floor = defaults.get("min_base_ms", 0) / 1000.0
                    if tc < floor:
                        raise TooFast(f"control run {tc*1000:.0f}ms < "
                                      f"{floor*1000:.0f}ms floor — this ratio "
                                      f"would measure process startup")
                    ratio = ts / tc if tc else float("inf")
                    unit = f"{ts*1000:.0f}ms vs {tc*1000:.0f}ms at n={n}"
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
                if isinstance(e, TooFast) and counted_here and eng in COUNTING:
                    too_fast[eng] = str(e)
                    continue
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
                # got fixed and whose marker stayed behind. Red since 2026-10-02:
                # printed in green, the marker outlived the fix and would have
                # covered the next regression of the same case in silence — the
                # open door `@reject-pending` (PROMOTE), ZyDDT's STALE WORDING
                # and its own `open_finding` (VERDICTS.md § 12) all refuse.
                print(f"          {C['red']}DEBT PAID — {known} now passes: close "
                      f"the finding and drop `open_finding`{C['off']}")
                rc = RED if rc != NOVERDICT else rc
        # ── The same question, counted instead of timed ───────────────────────
        #
        # A growth case is also asked in `zymbol run --count`'s units, where the
        # answer is exact. Three ratios, because each sees what the others do
        # not: `steps` is the engine's own work, `bytes` is what it asked the
        # allocator for, and `copied` is elements duplicated because a
        # collection being written had another owner — the shape of every
        # quadratic cost this harness was built after. Only the Rust engines
        # count; zyjs is asked by the clock above and nowhere else.
        if counted_here:
            n, f = case.get("count_n", defaults.get("count_n", 2000)), case["factor"]
            tpl = ROOT / case["template"]
            for eng in case.get("engines", defaults.get("engines", [])):
                if eng not in COUNTING:
                    continue
                try:
                    a, b = render(tpl, n), render(tpl, n * f)
                    tmp += [a, b]
                    ca, cb = counted(ENGINES[eng](a), ROOT), counted(ENGINES[eng](b), ROOT)
                except Exception as e:                  # noqa: BLE001
                    print(f"    {C['yellow']}NO VERDICT{C['off']}  {eng:5s}  counted: {e}")
                    if eng in too_fast:
                        # The clock was set aside on the strength of a count
                        # that never came: nothing answered this engine.
                        print(f"    {C['yellow']}NO VERDICT{C['off']}  {eng:5s}  "
                              f"{too_fast[eng]} — and the counted ratios could not be taken")
                    rc = max(rc, NOVERDICT)
                    continue
                rows = []
                for metric, lim in limits.items():
                    x, y = ca[metric], cb[metric]
                    ratio = (y / x) if x else (0.0 if y == 0 else float("inf"))
                    rows.append((metric, lim, x, y, ratio, ratio <= lim))
                if eng in too_fast:
                    # Said in the same breath as its reason, and before the rows
                    # that answer it: an exclusion whose reason is somewhere
                    # else is indistinguishable from a bug somebody hid. When
                    # the counts fail the line still says so — they are the
                    # verdict, and the gate is RED on them.
                    how = ("answer it, exactly and with no floor"
                           if all(r[-1] for r in rows)
                           else "do not pass, and they are the verdict")
                    print(f"    {C['dim']}SKIPPED{C['off']}  {eng:5s}  timed ratio: "
                          f"{too_fast[eng]}; the counted ratios below {how}")
                    skipped += 1
                for metric, lim, x, y, ratio, ok in rows:
                    tag = f"{C['green']}PASS{C['off']}" if ok else f"{C['red']}FAIL{C['off']}"
                    print(f"    {tag}  {eng:5s}  ratio {ratio:5.2f}  limit {lim:4.2f}   "
                          f"{C['dim']}{metric} {x}→{y} at ×{f}, counted{C['off']}")
                    if not ok:
                        print(f"          {C['dim']}{case['why']}{C['off']}")
                        rc = RED if rc != NOVERDICT else rc
        print()

    for f in tmp:
        f.unlink(missing_ok=True)

    if rc == GREEN:
        # Not folded into the word GREEN: how many clock readings the floor
        # set aside is part of what the verdict stands on.
        note = (f"; {skipped} timed ratio(s) under the floor, answered by the counted ones"
                if skipped else "")
        print(f"  {C['green']}{C['bold']}GREEN{C['off']} — every ratio within its declared limit{note}")
    elif rc == RED:
        print(f"  {C['red']}{C['bold']}RED{C['off']} — a declared cost ratio was exceeded")
    else:
        print(f"  {C['yellow']}{C['bold']}NO VERDICT{C['off']} — something could not be measured")
    return rc


if __name__ == "__main__":
    sys.exit(main())
