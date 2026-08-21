#!/usr/bin/env python3
"""Every corpus file through the language server, against `zymbol check`.

The LSP and the CLI are meant to run the same analysis on the same file. When
they disagree, one of them is wrong — and the disagreement is invisible from
either side alone, which is how it kept coming back.

The recurring cause is not a code defect at all: **a language server is a
process, and replacing its binary does not change the process**. Every
`cargo build` leaves the editor's server running the code it was started with,
so an editor opened before a release reports the previous release's rules —
errors on files that run perfectly. This script is how you tell that apart from
a real divergence: run it, and if it is clean while the editor is not, the
editor's server is stale and needs restarting, not fixing.

Usage:
    python3 lsp/lsp_parity.py [DIR] [--keep-open] [-v]

    DIR           what to sweep (default: corpus/)
    --keep-open   leave every document open, as an editor does, instead of
                  closing each one — the analyser keeps a document cache and a
                  symbol index, so the two are not the same question
    -v            list the disagreements the baseline already knows about

Binaries follow the same convention as engines.toml:
    ZYMBOL_BIN      the CLI              (default: `zymbol` on PATH)
    ZYMBOL_LSP_BIN  the language server  (default: `zymbol-lsp` on PATH)

Exit code 0 when every disagreement is in lsp/baseline.txt, 1 otherwise.
"""
import json, os, queue, re, subprocess, sys, threading, time
from urllib.parse import quote

HERE     = os.path.dirname(os.path.abspath(__file__))
ROOT     = os.path.dirname(HERE)
LSP      = os.environ.get("ZYMBOL_LSP_BIN", "zymbol-lsp")
CHECK    = os.environ.get("ZYMBOL_BIN", "zymbol")
BASELINE = os.path.join(HERE, "baseline.txt")
ANSI     = re.compile(r"\x1b\[[0-9;]*m")


def frame(obj):
    b = json.dumps(obj).encode()
    return b"Content-Length: %d\r\n\r\n" % len(b) + b


class Client:
    """The smallest LSP client that can ask for diagnostics."""

    def __init__(self):
        self.p = subprocess.Popen([LSP], stdin=subprocess.PIPE,
                                  stdout=subprocess.PIPE, stderr=subprocess.DEVNULL)
        self.q = queue.Queue()
        threading.Thread(target=self._read, daemon=True).start()
        self.id = 0

    def _read(self):
        f = self.p.stdout
        while True:
            line = f.readline()
            if not line:
                return
            if line.startswith(b"Content-Length:"):
                n = int(line.split(b":")[1].strip())
                f.readline()                      # the blank line
                try:
                    self.q.put(json.loads(f.read(n)))
                except Exception:
                    pass

    def send(self, obj):
        self.p.stdin.write(frame(obj))
        self.p.stdin.flush()

    def request(self, method, params):
        self.id += 1
        self.send({"jsonrpc": "2.0", "id": self.id, "method": method, "params": params})

    def notify(self, method, params):
        self.send({"jsonrpc": "2.0", "method": method, "params": params})

    def diagnostics(self, uri, timeout=8.0):
        end = time.time() + timeout
        while time.time() < end:
            try:
                msg = self.q.get(timeout=0.2)
            except queue.Empty:
                continue
            if msg.get("method") == "textDocument/publishDiagnostics" \
               and msg["params"].get("uri") == uri:
                return msg["params"].get("diagnostics", [])
        return None


def first_line(msg):
    """Both sides open with the same sentence; the LSP glues note/help onto it."""
    stripped = ANSI.sub("", msg or "")
    return stripped.splitlines()[0].strip() if stripped else ""


def cli_errors(path):
    env = dict(os.environ, NO_COLOR="1", TERM="dumb")
    r = subprocess.run([CHECK, "check", path], capture_output=True, text=True, env=env)
    out = ANSI.sub("", r.stdout + r.stderr)
    return [l.strip()[6:].strip() for l in out.splitlines() if l.strip().startswith("error:")]


def load_baseline():
    known = {}
    if not os.path.exists(BASELINE):
        return known
    for line in open(BASELINE, encoding="utf-8"):
        line = line.split("#", 1)[0].strip()
        if not line:
            continue
        path, _, kind = line.partition("\t")
        known[path.strip()] = kind.strip()
    return known


def main():
    args = [a for a in sys.argv[1:] if not a.startswith("-")]
    target = os.path.join(ROOT, args[0]) if args else os.path.join(ROOT, "corpus")
    keep_open = "--keep-open" in sys.argv
    verbose = "-v" in sys.argv

    files = []
    for d, _, fs in os.walk(target):
        if ".git" in d:
            continue
        files += [os.path.join(d, f) for f in sorted(fs) if f.endswith(".zy")]

    c = Client()
    c.request("initialize", {"processId": os.getpid(),
                             "rootUri": "file://" + quote(os.path.abspath(target)),
                             "capabilities": {}})
    time.sleep(0.6)
    c.notify("initialized", {})

    known = load_baseline()
    rows, new = [], []
    for path in files:
        ap = os.path.abspath(path)
        uri = "file://" + quote(ap)
        try:
            src = open(ap, encoding="utf-8").read()
        except Exception:
            continue
        c.notify("textDocument/didOpen", {"textDocument": {
            "uri": uri, "languageId": "zymbol", "version": 1, "text": src}})
        diags = c.diagnostics(uri)
        if not keep_open:
            c.notify("textDocument/didClose", {"textDocument": {"uri": uri}})

        rel = os.path.relpath(ap, ROOT)
        if diags is None:
            rows.append((rel, "NO-ANSWER", [], []))
            continue
        lsp = [first_line(d["message"]) for d in diags if d.get("severity", 1) == 1]
        cli = cli_errors(ap)
        if sorted(lsp) == sorted(cli):
            continue
        kind = ("LSP-ONLY" if lsp and not cli else
                "CLI-ONLY" if cli and not lsp else "WORDING")
        rows.append((rel, kind, lsp, cli))
        if known.get(rel) != kind:
            new.append((rel, kind, lsp, cli))

    print("lsp parity  %d files · %d disagreements · %d not in baseline"
          % (len(files), len(rows), len(new)))
    for rel, kind, lsp, cli in (rows if verbose else new):
        print("  %-9s %s" % (kind, rel))
        for m in lsp[:3]:
            print("      LSP: %s" % m[:120])
        for m in cli[:2]:
            print("      CLI: %s" % m[:120])
    if not new:
        print("  every disagreement is one the baseline accounts for")
    return 1 if new else 0


sys.exit(main())
