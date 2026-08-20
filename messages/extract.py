#!/usr/bin/env python3
"""Extract every diagnostic an engine can emit, and diff the three inventories.

Why this exists
---------------
Comparing engines by running the corpus only finds the messages the corpus
happens to trigger. That found about thirty; the engines between them define
several hundred. A message no test reaches is exactly the one that will be wrong
when a user finally reaches it, and the corpus cannot grow to cover them all,
because most are reached only by malformed programs.

So this reads the SOURCE instead: every string that is prose addressed to a
reader, in all three engines, whether or not any test has ever hit it.

Two mistakes this file exists to not repeat
-------------------------------------------
1. **Anchoring on constructor names.** The first version harvested only literals
   following `Diagnostic::error(`, `new ZyError(` and friends. It missed every
   message built inside a helper — `tuple_immutable_msg`, `missing_key_msg` —
   which are precisely the ones that were unified by hand and most deserve
   checking. It reported `cannot modify tuple` as existing in zyjs and not in
   Rust, which is the opposite of true.

2. **Regex to the first placeholder.** `format!("expected {}, got {}")` and
   ```expected ${a}, got ${b}``` are the same message, but a regex that stops at
   the first `{` splits them. That produced 54 false differences.

So: read balanced literals, join adjacent concatenations, and keep anything that
reads like a sentence. Over-collecting is harmless — the signal is which prose
exists in one engine and not the other.
"""
import io, os, re, sys

def read_literal(src, i):
    """Read the string literal at src[i]. Returns (text, index-after)."""
    q, out, i = src[i], [], i + 1
    while i < len(src):
        c = src[i]
        if c == '\\':
            out.append(src[i:i+2]); i += 2; continue
        if c == q:
            return ''.join(out), i + 1
        out.append(c); i += 1
    return ''.join(out), i

def all_literals(src, quotes):
    """Every string literal, with adjacent `+`-concatenations joined.

    Joining matters: zyjs builds its longer messages as several template pieces,
    and comparing only the first piece makes an identical message look different.
    """
    out, i, n = [], 0, len(src)
    while i < n:
        c = src[i]
        if c == '/' and i + 1 < n and src[i+1] == '/':          # line comment
            while i < n and src[i] != '\n': i += 1
            continue
        if c == '/' and i + 1 < n and src[i+1] == '*':          # block comment
            i = src.find('*/', i); i = n if i < 0 else i + 2; continue
        if c in quotes:
            text, j = read_literal(src, i)
            # join `"a" + "b"` / `"a"\n  "b"` runs
            while True:
                k = j
                while k < n and src[k] in ' \t\r\n': k += 1
                if k < n and src[k] == '+':
                    k += 1
                    while k < n and src[k] in ' \t\r\n': k += 1
                if k < n and src[k] in quotes:
                    more, j2 = read_literal(src, k)
                    text += more; j = j2; continue
                break
            out.append(text); i = j; continue
        i += 1
    return out

# A message is prose: several words, at least one space, and not a format spec,
# a path, an identifier list or a chunk of markup.
WORDY = re.compile(r'[a-z]{2,}\s+[a-z]{2,}', re.I)
# Code that reached the harvest by accident. A JS regex literal contains quotes,
# so the literal reader walks straight into the surrounding source and glues two
# unrelated strings together; rather than teach it JS's regex grammar — which
# needs the whole expression context to get right — reject anything that reads
# like code afterwards. Over-rejecting here costs a message; under-rejecting
# costs a false difference, and a false difference is what sends someone
# "fixing" an engine that was correct.
CODEY = re.compile(r'(return |mkStr\(|=> |\)\)|function\(|this\.[a-z]+\(|;\s*$)')
def is_message(s):
    t = s.strip()
    if len(t) < 12 or not WORDY.search(t): return False
    if t.startswith(('http', '/', '\\', 'target/', 'crates/')): return False
    if t.count('%') > 2 or t.count('<') > 2: return False
    if CODEY.search(t): return False
    return True

def norm(s):
    """Placeholders to one marker; case and trailing punctuation dropped."""
    s = re.sub(r'\$\{(?:[^{}]|\{[^{}]*\})*\}', '§', s)
    s = re.sub(r'\{(?:[^{}]|\{[^{}]*\})*\}', '§', s)
    for a, b in (('\\n', ' '), ('\\"', '"'), ("\\'", "'"), ('\\`', '`'), ('\\\\', '\\')):
        s = s.replace(a, b)
    return re.sub(r'\s+', ' ', s).strip().rstrip('.:;— -').lower()

def harvest(paths, quotes):
    out = {}
    for p in paths:
        src = io.open(p, encoding='utf-8', errors='replace').read()
        for t in all_literals(src, quotes):
            if is_message(t):
                out.setdefault(norm(t), (t, p))
    return out

def rust_files(root):
    for d, _, fs in os.walk(root):
        if '/target/' in d: continue
        for fn in fs:
            if fn.endswith('.rs') and not fn.startswith('test'):
                yield os.path.join(d, fn)

def main():
    R = harvest(rust_files('interpreter/crates'), '"')
    J = harvest(['web/src/zymbol/zymbol.js'], '"\'`')
    same, only_r, only_j = sorted(set(R) & set(J)), sorted(set(R) - set(J)), sorted(set(J) - set(R))
    print('  Rust  %4d · zyjs %4d' % (len(R), len(J)))
    print('  coinciden %4d · sólo Rust %4d · sólo zyjs %4d' % (len(same), len(only_r), len(only_j)))
    if '--only-js' in sys.argv:
        print('\n── sólo en zyjs ──')
        for k in only_j: print('   ', J[k][0].replace('\\n', ' ⏎ ')[:104])
    if '--only-rust' in sys.argv:
        print('\n── sólo en Rust ──')
        for k in only_r: print('   ', R[k][0].replace('\\n', ' ⏎ ')[:104])
    if '--same' in sys.argv:
        print('\n── coinciden ──')
        for k in same: print('   ', k[:104])

if __name__ == '__main__':
    main()
