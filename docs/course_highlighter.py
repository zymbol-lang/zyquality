#!/usr/bin/env python3
"""The course colours its code with the playground's highlighter, not a copy.

GLB-006 (decided 2026-10-05): `aprende_zymbol/` used to carry its own port of
the playground's highlighter, which drifted until it left 2555 corpus lines with
unmarked text against the playground's 0. The course now imports the module the
playground ships, from the published site. Three things keep that true:

  1. `index.html` imports `highlightCode` from the published path, and that path
     is a file the web repository has, exporting `highlightCode`;
  2. no script in the course defines a highlighter of its own;
  3. the course's CSS styles every `t-*` class the highlighter emits.

It reads files and runs nothing. Exit 0 when all three hold, 1 otherwise.
"""
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.normpath(os.path.join(HERE, "..", ".."))
COURSE = os.path.join(ROOT, "aprende_zymbol")
WEB = os.path.join(ROOT, "web")
SITE = "https://zymbol-lang.org/"

failures = []

index = open(os.path.join(COURSE, "index.html"), encoding="utf-8").read()
m = re.search(r"import\s*\{\s*highlightCode\s*\}\s*from\s*'([^']+)'", index)
if not m:
    failures.append("index.html does not import highlightCode from the playground")
else:
    url = m.group(1)
    if not url.startswith(SITE):
        failures.append(f"index.html imports the highlighter from {url}, not from {SITE}")
    else:
        local = os.path.join(WEB, url[len(SITE):])
        if not os.path.isfile(local):
            failures.append(f"{url} names {os.path.relpath(local, ROOT)}, which the web repository does not have")
        elif not re.search(r"export function highlightCode\b", open(local, encoding="utf-8").read()):
            failures.append(f"{os.path.relpath(local, ROOT)} no longer exports highlightCode")

own = re.compile(r"function\s+\w*[Hh]ighlight(?:Line|Code)\b")
for dirpath, _, names in os.walk(COURSE):
    if ".git" in dirpath.split(os.sep):
        continue
    for n in names:
        if n.endswith(".js"):
            p = os.path.join(dirpath, n)
            if own.search(open(p, encoding="utf-8").read()):
                failures.append(f"{os.path.relpath(p, ROOT)} defines a highlighter of its own — a copy drifts (GLB-006)")

hl = open(os.path.join(WEB, "src", "playground", "highlight.js"), encoding="utf-8").read()
emitted = set(re.findall(r"""class="(t-[a-z]+)|'(t-[a-z]+)'""", hl))
emitted = {a or b for a, b in emitted}
css = open(os.path.join(COURSE, "style.css"), encoding="utf-8").read()
for cls in sorted(emitted):
    if not re.search(r"\." + re.escape(cls) + r"\b\s*\{", css):
        failures.append(f"style.css does not style .{cls}, which the highlighter emits")

if failures:
    for f in failures:
        print(f"  ✗ {f}")
    sys.exit(1)
print(f"  ✓ the course imports the playground's highlighter; no copy; {len(emitted)} classes styled")
