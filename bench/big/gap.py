#!/usr/bin/env python3
"""ZyGap — how far each operation is from Python.

Python is the ORACLE (the value has to agree) and the time REFERENCE (the aim
is to get close, not to win). Every operation exists as a Zymbol program and a
Python twin that print the same thing; each times its OWN work from inside
(std/time, time.perf_counter), so neither start-up nor the difference of two
runs enters the figure.

Every operation is measured at n and at 2n. The gap is Zymbol's time over
Python's. If the gap GROWS from n to 2n the difference is not a constant but an
algorithm, and that is the defect most worth fixing: the row is marked `grows`.

The time unit (see instruments.py) is instructions:u where perf is allowed —
the hot part isolated as the program minus the same program without it — and
each program's own timer where it is not. Beside it, the Zymbol side's
`--count` steps for the hot part alone, which are exact.

  python3 gap.py                                 # VM and tree-walker, median of 3
  python3 gap.py --runs 5 --only arr_update_each,str_iter --json out.json
  python3 gap.py --no-tw                         # the VM only

ZYMBOL_BIN chooses the binary (default: `zymbol` on PATH).
Exit 0 when every value agrees with Python, 1 when one does not, 2 on a usage
error.
"""
import argparse, json, os, re, statistics as st, subprocess, sys, tempfile

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))   # `python3 -I` leaves it out
from instruments import Meter, counted                              # noqa: E402

ANSI = re.compile(r'\x1b\[[0-9;]*m')
CH = '0123456789abcdefghijklmnopqrstuvwxyz0123456789abcdefghijklmnopqrstuvwxyz'  # 72 characters

Z_ARR = 'v = []\n@ i:1..n { v = v $+ i }\n'
P_ARR = 'v = list(range(1, n + 1))\n'
Z_LCG = 'v = []\nx = 12345\n@ _i:1..n {\n    x = (x * 1103 + 12345) % 1000003\n    v = v $+ x\n}\n'
P_LCG = 'v = []\nx = 12345\nfor _ in range(n):\n    x = (x * 1103 + 12345) % 1000003\n    v.append(x)\n'
Z_STR = 'chunk = "%s"\ns = ""\n@ _c:1..(n / 72) { s = s chunk }\n' % CH
P_STR = 'chunk = "%s"\ns = chunk * (n // 72)\n' % CH
Z_DICT = 'd = #()\n@ i:1..n {\n    kk = "k" i\n    d[kk]$~ i\n}\n'
P_DICT = 'd = {}\nfor i in range(1, n + 1):\n    d["k" + str(i)] = i\n'

# name, kind, (n, k) small, (n, k) large,
#   Zymbol setup, hot part, result;  Python setup, hot part, result
# `total`: the work is of size n.  `percall`: a structure of size n and k fixed
# operations on it, so the time should not depend on n.
OPS = [
 ('arr_append', 'total', (1000000, 0), (2000000, 0), '', 'v = []\n@ i:1..n { v = v $+ i }', 'v$#', '', 'v = []\nfor i in range(1, n + 1):\n    v.append(i)', 'len(v)'),
 ('arr_read', 'total', (500000, 0), (1000000, 0), Z_ARR, 's = 0\n@ i:1..n { s = s + v[i] }', 's', P_ARR, 's = 0\nfor i in range(n):\n    s += v[i]', 's'),
 ('arr_foreach', 'total', (500000, 0), (1000000, 0), Z_ARR, 's = 0\n@ x:v { s = s + x }', 's', P_ARR, 's = 0\nfor x in v:\n    s += x', 's'),
 ('arr_update_each', 'total', (8000, 0), (16000, 0), 'v = []\n@ i:1..n { v = v $+ 0 }\n', '@ i:1..n { v[i]$~ i }', 'v[n]', 'v = [0] * n\n', 'for i in range(1, n + 1):\n    v[i - 1] = i', 'v[n - 1]'),
 ('arr_remove_last', 'total', (8000, 0), (16000, 0), Z_ARR, '@ i:1..n { v = v $-[(n - i + 1)] }', 'v$#', P_ARR, 'for i in range(1, n + 1):\n    del v[n - i]', 'len(v)'),
 ('map_filter_reduce', 'total', (500000, 0), (1000000, 0), Z_ARR, 'a = v $> (x -> x * 2)\nb = a $| (x -> x % 3 == 0)\nc = b $< (0, (acc, x) -> acc + x)', 'c',
  'from functools import reduce\n' + P_ARR, 'a = list(map(lambda x: x * 2, v))\nb = list(filter(lambda x: x % 3 == 0, a))\nc = reduce(lambda acc, x: acc + x, b, 0)', 'c'),
 ('sort_builtin', 'total', (500000, 0), (1000000, 0), Z_LCG, 'r = v $^+', 'r[1]', P_LCG, 'r = sorted(v)', 'r[0]'),
 ('sort_comparator', 'total', (50000, 0), (100000, 0), Z_LCG, 'r = v $^ (p, q -> p < q)', 'r[1]',
  'from functools import cmp_to_key\n' + P_LCG, 'r = sorted(v, key=cmp_to_key(lambda p, q: -1 if p < q else (1 if p > q else 0)))', 'r[0]'),
 ('str_concat', 'total', (64000, 0), (128000, 0), '', 's = ""\n@ i:1..n { s = s "x" }', 's$#', '', 's = ""\nfor i in range(n):\n    s += "x"', 'len(s)'),
 ('str_interp', 'total', (500000, 0), (1000000, 0), '', 'c = 0\n@ i:1..n {\n    t = "{i}"\n    c = c + t$#\n}', 'c', '', 'c = 0\nfor i in range(1, n + 1):\n    t = str(i)\n    c += len(t)', 'c'),
 ('dict_insert', 'total', (4000, 0), (8000, 0), '', 'd = #()\n@ i:1..n {\n    kk = "k" i\n    d[kk]$~ i\n}', 'd["k1"]', '', 'd = {}\nfor i in range(1, n + 1):\n    d["k" + str(i)] = i', 'd["k1"]'),
 ('call_overhead', 'total', (1000000, 0), (2000000, 0), 'f(x) { <~ x + 1 }\n', 's = 0\n@ i:1..n { s = f(s) }', 's', 'def f(x):\n    return x + 1\n', 's = 0\nfor i in range(n):\n    s = f(s)', 's'),
 ('closure_create_call', 'total', (500000, 0), (1000000, 0), '', 's = 0\n@ i:1..n {\n    g = (x -> x + i)\n    s = s + g(1)\n}', 's', '', 's = 0\nfor i in range(1, n + 1):\n    g = lambda x, i=i: x + i\n    s += g(1)', 's'),
 ('match_range', 'total', (1000000, 0), (2000000, 0), '', 'c = 0\n@ i:1..n {\n    c = c + ?? (i % 100) {\n        0..9 => 1\n        10..49 => 2\n        _ => 3\n    }\n}', 'c',
  '', 'c = 0\nfor i in range(1, n + 1):\n    m = i % 100\n    if 0 <= m <= 9:\n        c += 1\n    elif 10 <= m <= 49:\n        c += 2\n    else:\n        c += 3', 'c'),
 ('print_lines', 'total', (100000, 0), (200000, 0), '', '@ i:1..n { >> i ¶ }', '"fin"', '', 'for i in range(1, n + 1):\n    print(i)', '"fin"'),
 ('str_iter', 'percall', (147456, 1), (294912, 1), Z_STR, 'c = 0\n@ ch:s {\n    ? ch == \'a\' { c = c + 1 }\n}', 'c', P_STR, 'c = 0\nfor ch in s:\n    if ch == "a":\n        c += 1', 'c'),
 ('str_split', 'percall', (80000, 1), (160000, 1), 's = ""\n@ _i:1..(n / 8) { s = s "abc,def," }\n', 'p = s $/ \',\'', 'p$#', 's = "abc,def," * (n // 8)\n', 'p = s.split(",")', 'len(p)'),
 ('arr_update_one', 'percall', (50000, 2000), (100000, 2000), Z_ARR, '@ i:1..k { v[1]$~ i }', 'v[1]', P_ARR, 'for i in range(1, k + 1):\n    v[0] = i', 'v[0]'),
 ('arr_slice_small', 'percall', (200000, 2000), (400000, 2000), Z_ARR, 't = []\n@ i:1..k { t = v$[1..10] }', 't$#', P_ARR, 'for i in range(k):\n    t = v[0:10]', 'len(t)'),
 ('arr_len', 'percall', (200000, 20000), (400000, 20000), Z_ARR, 'm = 0\n@ i:1..k { m = v$# }', 'm', P_ARR, 'for i in range(k):\n    m = len(v)', 'm'),
 ('arr_pass_to_function', 'percall', (200000, 5000), (400000, 5000), 'f(a) { <~ a[1] }\n' + Z_ARR, 'm = 0\n@ i:1..k { m = f(v) }', 'm', 'def f(a):\n    return a[0]\n' + P_ARR, 'for i in range(k):\n    m = f(v)', 'm'),
 ('arr_get_middle', 'percall', (200000, 20000), (400000, 20000), Z_ARR, 'm = 0\n@ i:1..k { m = v[(n / 2)] }', 'm', P_ARR, 'for i in range(k):\n    m = v[n // 2 - 1]', 'm'),
 ('str_len', 'percall', (73728, 20000), (147456, 20000), Z_STR, 'm = 0\n@ i:1..k { m = s$# }', 'm', P_STR, 'for i in range(k):\n    m = len(s)', 'm'),
 ('str_slice_small', 'percall', (73728, 2000), (147456, 2000), Z_STR, 't = ""\n@ i:1..k { t = s$[1..10] }', 't', P_STR, 'for i in range(k):\n    t = s[0:10]', 't'),
 ('dict_lookup', 'percall', (2000, 200000), (4000, 200000), Z_DICT, 'm = 0\n@ i:1..k { m = d["k1"] }', 'm', P_DICT, 'for i in range(k):\n    m = d["k1"]', 'm'),
 # Added 2026-10-14: `dict_lookup` reads the key inserted FIRST, which a linear search finds at
 # once, so it read as flat while the lookup was linear (PERF-03). This reads the last one.
 ('dict_lookup_last', 'percall', (2000, 20000), (4000, 20000), Z_DICT + 'last = "k" n\n', 'm = 0\n@ i:1..k { m = d[last] }', 'm',
  P_DICT + 'last = "k" + str(n)\n', 'for i in range(k):\n    m = d[last]', 'm'),
 ('dict_update_existing', 'percall', (2000, 1000), (4000, 1000), Z_DICT, '@ i:1..k { d["k1"]$~ i }', 'd["k1"]', P_DICT, 'for i in range(1, k + 1):\n    d["k1"] = i', 'd["k1"]'),
]


def zy_src(setup, hot, res):
    return ('<# std/time => clock\n>< 引数\nn = #|引数[1]|\nk = #|引数[2]|\n' + setup + 't0 = clock::now()\n' + hot +
            '\nt1 = clock::now()\n>> ' + res + ' ¶\n>> "T=" (t1 - t0) ¶\n')


def py_src(setup, hot, res):
    """The twin runs INSIDE a function: in CPython locals are faster than
    globals, and that is the Python worth measuring against. At module level
    `s += "x"` is quadratic in CPython too, which gave Zymbol a parity it had
    not earned."""
    body = 'n = int(sys.argv[1])\nk = int(sys.argv[2])\n' + setup + 't0 = time.perf_counter()\n' + hot + \
           '\nt1 = time.perf_counter()\nprint(' + res + ')\nprint("T=" + str(round((t1 - t0) * 1000, 3)))\n'
    return 'import sys, time\n\ndef main():\n' + ''.join(('    ' + l if l.strip() else l) + '\n' for l in body.split('\n')).rstrip(' \n') + '\n\nmain()\n'


def run(cmd):
    """One plain run → ((inner ms, printed value), 'OK') or (None, why)."""
    try:
        r = subprocess.run(cmd, capture_output=True, timeout=300, stdin=subprocess.DEVNULL)
    except subprocess.TimeoutExpired:
        return None, 'TIMEOUT'
    out = ANSI.sub('', r.stdout.decode('utf-8', 'replace')).strip().split('\n')
    if r.returncode != 0 or not out or not out[-1].startswith('T='):
        msg = ANSI.sub('', (r.stderr.decode('utf-8', 'replace') + ' ' + '\n'.join(out[-3:]))).strip().replace('\n', ' ')
        return None, 'ERROR ' + msg[:80]
    return (float(out[-1][2:]), '\n'.join(out[:-1])), 'OK'


def side(meter, cmd, base, runs, zymbol):
    """→ dict for one side at one size: the value it printed, its time in the
    run's unit, and — Zymbol only — its exact `--count` steps and bytes.

    In instructions the hot part is isolated by subtraction: the same program
    with the hot part left out (`base`) costs the setup and start-up, and both
    are near-exact. With the clock, the program's own timer is used instead:
    it already leaves both out, and a difference of two clock readings would
    be noisier than either."""
    first, status = run(cmd)
    if first is None:
        return {'status': status, 'value': None, 't': None, 'steps': None, 'bytes': None}
    res = {'status': 'OK', 'value': first[1], 'steps': None, 'bytes': None}
    if meter.unit == 'instructions':
        full, bt = meter(cmd)[0], meter(base)[0]
        res['t'] = max(full - bt, 0.0) if (full is not None and bt is not None) else None
    else:
        inner = [first[0]] + [r[0][0] for r in (run(cmd) for _ in range(runs - 1)) if r[0]]
        res['t'] = st.median(inner)
    if zymbol:
        fc, bc = counted(cmd)[0], counted(base)[0]
        if fc and bc:
            res['steps'], res['bytes'] = fc['steps'] - bc['steps'], fc['bytes'] - bc['bytes']
    return res


def gap(z, p, unit):
    """Zymbol over Python, or None where the Zymbol side is too small to be a
    value: under 5 ms of its own timer (it prints whole milliseconds), or under
    a million instructions."""
    floor = 1e6 if unit == 'instructions' else 5
    return z / p if (z is not None and z >= floor and p) else None


def human(n):
    if n is None:
        return '—'
    for unit, size in (('G', 1e9), ('M', 1e6), ('k', 1e3)):
        if abs(n) >= size:
            return '%.1f%s' % (n / size, unit)
    return '%d' % n


def main():
    ap = argparse.ArgumentParser(description=__doc__.split('\n\n')[0])
    ap.add_argument('--runs', type=int, help='runs per median (default 7 with perf, 3 with the clock)')
    ap.add_argument('--clock', action='store_true', help="use the programs' own timers even where perf is available")
    ap.add_argument('--only', default='', help='comma-separated operation names')
    ap.add_argument('--json', default='', metavar='PATH', help='also write the results here')
    ap.add_argument('--no-tw', action='store_true', help='measure the VM only')
    a = ap.parse_args()
    if a.runs is not None and a.runs < 1:
        ap.error('--runs must be at least 1')
    zy = os.environ.get('ZYMBOL_BIN', 'zymbol')
    try:
        ver = subprocess.run([zy, '--version'], capture_output=True, text=True).stdout.strip()
    except FileNotFoundError:
        print('gap.py: no `%s` — install it, or set ZYMBOL_BIN to a build' % zy, file=sys.stderr)
        return 2
    if a.only:
        unknown = [w for w in a.only.split(',') if w not in [o[0] for o in OPS]]
        if unknown:
            ap.error('no such operation: ' + ', '.join(unknown))
    meter = Meter(force_clock=a.clock, runs=a.runs)
    runs = meter.runs if (a.runs or meter.unit == 'instructions') else 3
    unit = meter.unit if meter.unit == 'instructions' else 'inner-ms'
    print('%s (%s) | Python %s' % (ver, zy, sys.version.split()[0]))
    if meter.unit == 'instructions':
        print(meter.header() + ' — the hot part alone: the program minus itself without it')
    else:
        print("time unit: each program's own timer, median of %d — perf unavailable (%s)" % (runs, meter.reason))
    print('steps: `zymbol run --count` of the hot part alone, exact')
    print('gap = Zymbol / Python; `grows` = the gap rises when n doubles (an algorithm, not a constant)\n')
    print('%-22s %-8s %16s | %8s %8s %7s %8s | %8s %8s %7s %8s | %s' % (
        'operation', 'kind', 'n', 'Py', 'VM', 'VM/Py', 'steps', 'Py', 'VM', 'VM/Py', 'steps', ''))
    rows, differ = [], []
    with tempfile.TemporaryDirectory(prefix='zygap-') as tmp:
        for name, kind, s1, s2, zs, zh, zr, ps, ph, pr in OPS:
            if a.only and name not in a.only.split(','):
                continue
            files = {}
            for tag, text in (('zy', zy_src(zs, zh, zr)), ('zy0', zy_src(zs, '', '"base"')),
                              ('py', py_src(ps, ph, pr)), ('py0', py_src(ps, 'pass', '"base"'))):
                files[tag] = os.path.join(tmp, '%s.%s.%s' % (name, tag, 'zy' if tag.startswith('zy') else 'py'))
                open(files[tag], 'w', encoding='utf-8').write(text)
            row = {'op': name, 'kind': kind, 'unit': unit, 'sizes': []}
            for (n, k) in (s1, s2):
                args = [str(n), str(k)]
                py = side(meter, [sys.executable, '-I', files['py']] + args,
                          [sys.executable, '-I', files['py0']] + args, runs, False)
                # Both engines by name: since v0.0.11 a bare `run` is the VM.
                vm = side(meter, [zy, 'run', '--vm', files['zy']] + args,
                          [zy, 'run', '--vm', files['zy0']] + args, runs, True)
                tw = None if a.no_tw else side(meter, [zy, 'run', '--tw', files['zy']] + args,
                                               [zy, 'run', '--tw', files['zy0']] + args, runs, True)
                vm['ok'] = py['value'] is not None and vm['value'] == py['value']
                if not vm['ok']:
                    differ.append('%s n=%d: VM %s' % (name, n, vm['status'] if vm['status'] != 'OK' else repr(vm['value'])[:40]))
                if tw is not None:
                    tw['ok'] = py['value'] is not None and tw['value'] == py['value']
                    if not tw['ok']:
                        differ.append('%s n=%d: TW %s' % (name, n, tw['status'] if tw['status'] != 'OK' else repr(tw['value'])[:40]))
                row['sizes'].append({'n': n, 'k': k, 'py': py, 'vm': vm, 'tw': tw})
            rows.append(row)
            cells = []
            fmt = (lambda v: human(v)) if unit == 'instructions' else \
                  (lambda v: '—' if v is None else ('%.1f' % v if v < 10 else '%.0f' % v))
            for s in row['sizes']:
                g = gap(s['vm']['t'], s['py']['t'], unit)
                cells.append('%8s %8s %7s %8s' % (fmt(s['py']['t']), fmt(s['vm']['t']),
                                                  '%7.1f' % g if g else '      ~', human(s['vm']['steps'])))
            first, last = row['sizes']
            r1, r2 = gap(first['vm']['t'], first['py']['t'], unit), gap(last['vm']['t'], last['py']['t'], unit)
            row['gap_small'], row['gap_large'] = r1, r2
            flag = 'VALUE DIFFERS' if not (first['vm']['ok'] and last['vm']['ok']) else \
                   ('grows' if (r1 and r2 and r2 > 1.5 * r1 and r2 > 3) else '')
            size = '%d→%d' % (first['n'], last['n']) if kind == 'total' else '%dk' % (last['n'] // 1000)
            print('%-22s %-8s %16s | %s | %s | %s' % (name, kind, size, cells[0], cells[1], flag), flush=True)
    checked = sum(1 for r in rows for s in r['sizes'] for e in ('vm', 'tw') if s[e] is not None)
    print('\n%d of %d values agree with Python (VM%s).' % (checked - len(differ), checked, '' if a.no_tw else ' and tree-walker'))
    for d in differ:
        print('  ✗ ' + d)
    if a.json:
        with open(a.json, 'w', encoding='utf-8') as fh:
            json.dump({'zymbol': ver, 'binary': zy, 'python': sys.version.split()[0], 'unit': unit,
                       'unit_reason': meter.reason, 'runs': runs, 'rows': rows}, fh, indent=1, ensure_ascii=False)
    return 0 if rows and not differ else 1


if __name__ == '__main__':
    sys.exit(main())
