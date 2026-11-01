#!/usr/bin/env python3
"""
Verify the interpreter's LLM.md against the engines.

LLM.md is what a model reads before it writes Zymbol, and it opens by saying
every line of it was run.  Until 2026-10-11 nothing checked that: `guide_verify`
grades GUIDE.md by its `// →` annotations, and LLM.md is too dense to carry
them -- most of its blocks are tables of forms, not programs.  It had gathered
five false claims by the time anybody read it against the binary
(interpreter/IMPL_V009.md § E.3).

So this does not execute the document.  It executes PROBES, each of which quotes
the sentence it stands behind:

    docs/llm/05_function_scope.zy
        // claim: **A named function sees only its parameters.**
        // verdict: error
        // says: is read from outside this function
        x = 1
        f() { <~ x }
        >> f() ¶

and it fails in three ways, which are the three ways the document can rot:

  1. a probe no longer does what it declares, in any of the three engines --
     the LANGUAGE moved and the sentence is now false;
  2. a quoted sentence is no longer in LLM.md -- the DOCUMENT moved, and whoever
     edited it has to say whether the probe still stands behind the new words;
  3. a numbered rule of § 1 or a bullet of § 12 has no probe quoting it -- a
     claim was ADDED and nobody ran it.

The third is what makes this a gate on the document rather than a pile of
tests: a new rule cannot be written without something that runs.

Probe header (comment lines at the top of the file, any order):

    // claim:   text that must appear verbatim in LLM.md (whitespace-insensitive)
    // verdict: ok | warn | error          default ok
    // says:    text the diagnostics must contain   (warn, error)
    // quiet:   yes                         ok, and not one diagnostic
    // engines: zytw,zyvm                   default: all three
    // block:   heading text                the program IS the first ```zymbol
    //                                      block under that LLM.md heading
    //                                      (`heading #2` for the second one)
    // file:    name.zy                     starts another file; the last runs

In an `ok` probe every `// → value` is an expected output line, in order.  With
or without them, the engines' outputs must be identical.

    ZYMBOL_BIN=/usr/bin/zymbol ZY_LLM=/path/to/LLM.md python3 docs/llm_verify.py
    python3 docs/llm_verify.py --only 05      # one probe, with its output
"""

import os
import re
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

HERE   = Path(__file__).resolve().parent                 # zyquality/docs/
ROOT   = HERE.parent                                     # zyquality/
PROBES = HERE / "llm"
ZYMBOL = os.environ.get("ZYMBOL_BIN") or shutil.which("zymbol") or "zymbol"
LLM    = Path(os.environ.get("ZY_LLM") or (ROOT / ".." / "interpreter" / "LLM.md"))
ZYJS   = Path(os.environ.get("ZYJS_HARNESS") or (ROOT / ".." / "web" / "tests" / "run_one.mjs"))

ENGINES = {
    "zytw": lambda f: [ZYMBOL, "run", "--tw", f],
    "zyvm": lambda f: [ZYMBOL, "run", "--vm", f],
    "zyjs": lambda f: ["node", str(ZYJS), f],
}

ANSI     = re.compile(r"\x1b\[[0-9;]*m")
HEADER   = re.compile(r"^//\s*(claim|verdict|says|quiet|engines|block|file):\s*(.*?)\s*$")
ARROW    = re.compile(r"//\s*→\s*(.+?)\s*$")
DIAG     = re.compile(r"^(warning|error|note)\b|^Runtime error|^\s+-->|^\s+= (help|note)|^\s*\d*\s*\|")


def squash(text: str) -> str:
    """Whitespace-insensitive form: a claim may be wrapped where LLM.md is not."""
    return re.sub(r"\s+", " ", text).strip()


# ── the document ──────────────────────────────────────────────────────────────

class Document:
    def __init__(self, path: Path):
        self.text  = path.read_text(encoding="utf-8")
        self.flat  = squash(self.text)
        self.lines = self.text.splitlines()

    def has(self, claim: str) -> bool:
        return squash(claim) in self.flat

    def version(self):
        m = re.search(r"^# .*?v(\d+\.\d+\.\d+)", self.text, re.MULTILINE)
        return m.group(1) if m else None

    def section(self, number: int) -> list[str]:
        """The lines of `## N. …`, up to the next `## `."""
        out, inside = [], False
        for line in self.lines:
            if line.startswith("## "):
                inside = bool(re.match(rf"## {number}\.", line))
                continue
            if inside:
                out.append(line)
        return out

    def units(self) -> list[tuple[str, str]]:
        """
        The claims that must each have a probe: the numbered rules of § 1 and
        the bullets of § 12.  A unit runs from its marker to the next one.
        """
        found = []
        for number, marker, label in ((1, r"^\d+\. ", "§1 rule {}"), (12, r"^- ", "§12 bullet {}")):
            current, n = None, 0
            for line in self.section(number) + [""]:
                if re.match(marker, line):
                    if current is not None:
                        found.append((label.format(n), squash(current)))
                    current, n = line, n + 1
                elif current is not None and line.strip() and not line.startswith(("#", "```", "---")):
                    current += " " + line
                elif current is not None and not line.strip():
                    found.append((label.format(n), squash(current)))
                    current = None
        return found

    def block_under(self, heading: str):
        """
        A ```zymbol block under the heading that contains `heading`: the first,
        or the n-th when the heading is followed by ` #n`.
        """
        nth = 1
        if (m := re.search(r"\s+#(\d+)$", heading)):
            heading, nth = heading[:m.start()], int(m.group(1))
        at = next((i for i, l in enumerate(self.lines)
                   if l.startswith("#") and heading in l), None)
        if at is None:
            return None
        body, inside, seen = [], False, 0
        for line in self.lines[at + 1:]:
            if not inside and line.startswith("#"):
                return None
            if line.strip() == "```zymbol":
                inside, body = True, []
            elif inside and line.strip() == "```":
                seen += 1
                if seen == nth:
                    return "\n".join(body) + "\n"
                inside = False
            elif inside:
                body.append(line)
        return None


# ── a probe ───────────────────────────────────────────────────────────────────

class Probe:
    def __init__(self, path: Path, doc: Document):
        self.path    = path
        self.name    = path.stem
        self.claims  = []
        self.verdict = "ok"
        self.says    = []
        self.quiet   = False
        self.engines = list(ENGINES)
        self.files   = []                      # [(name, text)], the last one runs
        self.problem = None

        name, body, block = "main.zy", [], None
        for line in path.read_text(encoding="utf-8").splitlines():
            m = HEADER.match(line)
            if not m:
                body.append(line)
                continue
            key, value = m.groups()
            if key == "claim":
                self.claims.append(value)
            elif key == "verdict":
                self.verdict = value
            elif key == "says":
                self.says.append(value)
            elif key == "quiet":
                self.quiet = value.lower() in ("yes", "true", "1")
            elif key == "engines":
                self.engines = [e.strip() for e in value.split(",") if e.strip()]
            elif key == "block":
                block = value
            elif key == "file":
                if any(l.strip() for l in body):
                    self.files.append((name, "\n".join(body) + "\n"))
                name, body = value, []
        if block is not None:
            text = doc.block_under(block)
            if text is None:
                self.problem = f"no ```zymbol block under a heading containing {block!r}"
            body = (text or "").splitlines()
        self.files.append((name, "\n".join(body) + "\n"))

        if not self.claims:
            self.problem = "no `// claim:` — a probe has to say which sentence it stands behind"
        elif self.verdict not in ("ok", "warn", "error"):
            self.problem = f"unknown verdict {self.verdict!r}"
        elif [e for e in self.engines if e not in ENGINES]:
            self.problem = f"unknown engine in {self.engines}"

    def expected(self) -> list[str]:
        return [m.group(1) for line in self.files[-1][1].splitlines()
                if (m := ARROW.search(line))]


def run(probe: Probe, engine: str, workdir: str):
    """(exit code, program output lines, diagnostics as one string)."""
    for name, text in probe.files:
        target = Path(workdir) / name
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_text(text, encoding="utf-8")
    main = str(Path(workdir) / probe.files[-1][0])
    r = subprocess.run(ENGINES[engine](main), capture_output=True, text=True,
                       timeout=30, stdin=subprocess.DEVNULL, cwd=workdir)
    out  = [l.rstrip() for l in ANSI.sub("", r.stdout).splitlines() if l.strip()]
    diag = ANSI.sub("", r.stderr)
    # An engine that writes its diagnostics to stdout must not have them read
    # as the program's output: they are separated by shape, not by stream.
    program = [l for l in out if not DIAG.match(l)]
    diag += "\n".join(l for l in out if DIAG.match(l))
    return r.returncode, program, diag


def judge(probe: Probe, results: dict) -> list[str]:
    """Every way this probe failed; empty when it holds."""
    faults = []
    for engine, (rc, out, diag) in results.items():
        if probe.verdict == "error":
            if rc == 0:
                faults.append(f"{engine}: expected an error, and it ran — output {out[:3]}")
        else:
            if rc != 0:
                first = next((l for l in diag.splitlines() if l.strip()), "")
                faults.append(f"{engine}: exit {rc} — {first[:110]}")
        if probe.verdict == "ok" and probe.quiet and diag.strip():
            first = next(l for l in diag.splitlines() if l.strip())
            faults.append(f"{engine}: expected no diagnostic — {first[:110]}")
        for text in probe.says:
            if text not in diag:
                got = next((l for l in diag.splitlines() if l.strip()), "nothing")
                faults.append(f"{engine}: the diagnostics do not say {text!r} — they say: {got[:110]}")

    if probe.verdict != "error":
        want = probe.expected()
        for engine, (_rc, out, _diag) in results.items():
            if want and out != want:
                faults.append(f"{engine}: output {out}  ≠  expected {want}")
        outputs = {e: tuple(r[1]) for e, r in results.items()}
        if len(set(outputs.values())) > 1 and not any("≠" in f for f in faults):
            faults.append("the engines disagree: " +
                          "  ".join(f"{e}={list(o)}" for e, o in outputs.items()))
    return faults


# ── main ──────────────────────────────────────────────────────────────────────

def main() -> int:
    only = None
    if "--only" in sys.argv:
        only = sys.argv[sys.argv.index("--only") + 1]

    if not LLM.is_file():
        print(f"llm_verify: {LLM} not found", file=sys.stderr)
        return 2
    try:
        answer = subprocess.run([ZYMBOL, "--version"], capture_output=True, text=True, timeout=10)
        binary = answer.stdout.split()[-1]
    except Exception as e:
        print(f"llm_verify: cannot run {ZYMBOL}: {e}", file=sys.stderr)
        return 2
    have_js = ZYJS.is_file() and shutil.which("node")

    doc    = Document(LLM)
    probes = [Probe(p, doc) for p in sorted(PROBES.glob("*.zy"))]
    if only:
        probes = [p for p in probes if p.name.startswith(only)]
    if not probes:
        print("llm_verify: no probes", file=sys.stderr)
        return 2

    red, skipped_js = [], 0
    with tempfile.TemporaryDirectory() as tmp:
        for probe in probes:
            faults = []
            if probe.problem:
                faults.append(probe.problem)
            for claim in probe.claims:
                if not doc.has(claim):
                    faults.append(f"LLM.md no longer says: {claim}")
            results = {}
            if not probe.problem:
                for engine in probe.engines:
                    if engine == "zyjs" and not have_js:
                        skipped_js += 1
                        continue
                    work = os.path.join(tmp, f"{probe.name}.{engine}")
                    os.makedirs(work)
                    try:
                        results[engine] = run(probe, engine, work)
                    except subprocess.TimeoutExpired:
                        faults.append(f"{engine}: timeout")
                faults += judge(probe, results)
            if only:
                for engine, (rc, out, diag) in results.items():
                    print(f"  {engine}  rc={rc}  out={out}")
                    for line in diag.splitlines():
                        if line.strip():
                            print(f"      {line}")
            if faults:
                red.append((probe, faults))

    # A sentence that claims and has nothing that runs.
    quoted  = [squash(c) for p in probes for c in p.claims]
    units   = doc.units()
    orphans = [] if only else [(label, text) for label, text in units
                               if not any(q in text for q in quoted)]

    stale = None
    if doc.version() != binary:
        stale = f"LLM.md is titled v{doc.version()} and the binary is {binary}"

    width = 72
    print("=" * width)
    print(f"  LLM.md — every claim, behind a probe that runs   (zymbol {binary})")
    print(f"  {len(probes)} probes · {sum(len(p.claims) for p in probes)} sentences quoted · "
          f"{len(units) - len(orphans)} of {len(units)} rules and bullets covered")
    if skipped_js:
        print(f"  zyjs not available: {skipped_js} probe(s) asked two engines instead of three")
    print("=" * width)
    for probe, faults in red:
        print(f"\n  ✗ {probe.name}")
        for fault in faults:
            print(f"      {fault}")
    for label, text in orphans:
        print(f"\n  ✗ {label} has no probe:  {text[:96]}…")
    if stale:
        print(f"\n  ✗ {stale}")
    held = len(probes) - len(red)
    print(f"\n  PASS={held}  FAIL={len(red)}  UNCOVERED={len(orphans)}"
          f"{'  STALE TITLE' if stale else ''}\n")
    return 1 if (red or orphans or stale) else 0


if __name__ == "__main__":
    sys.exit(main())
