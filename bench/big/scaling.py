#!/usr/bin/env python3
"""ZyScale — hunts performance defects by their GROWTH CURVE.

It does not compare with Python. For each Zymbol operation it measures how long
it takes at n, 2n, 4n and 8n and fits the exponent b of time ~ n^b. An
operation that should be linear and comes out at b ~ 2 is a defect, whether or
not it beats Python.

Two kinds of operation:
  total    the whole work is of size n (n inserts, n turns...).
           b ~ 1 is expected (1.15 for a sort).
  percall  the structure has size n and K fixed operations run on it.
           b ~ 0 is expected: the cost of ONE operation should not depend on
           the size. The net time is t(K operations) - t(0 operations).
           (str_iter uses this kind with K = 1 and expects b ~ 1: one whole
           pass over the text, without what it took to build it.)

It also compares engines: a VM that comes out worse than the tree-walker, or
grows faster, has a slow path the tree-walker does not have.

Every curve is fitted three times (see instruments.py): in the time unit —
instructions:u where perf is allowed, CPU ms where it is not — and in the
`--count` units steps and bytes, which are exact. Where the time grows and
neither counter does, the cost is a scan inside one instruction: `--count`
cannot hold that finding, and a `cost/` case for it has to be by the clock.

  python3 scaling.py
  python3 scaling.py --only arr_update_each,str_iter --json out.json
  ZYMBOL_OLD=/path/to/other/zymbol python3 scaling.py --no-tw

ZYMBOL_BIN chooses the binary (default: `zymbol` on PATH); ZYMBOL_OLD adds a
second binary's VM as a third column. In CPU ms the `percall` subtraction is
noisy when building the structure takes seconds; in steps and bytes it is
exact. Exit 0 when nothing grows faster
than expected, 1 when something does, 2 on a usage error.
"""
import argparse, json, math, os, re, subprocess, sys, tempfile

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))   # `python3 -I` leaves it out
from instruments import Meter, counted, cpu_ms                      # noqa: E402

ANSI = re.compile(r'\x1b\[[0-9;]*m')
HEAD = '>< 引数\nn = #|引数[1]|\nk = #|引数[2]|\n'
CHUNK = '"0123456789abcdefghijklmnopqrstuvwxyz0123456789abcdefghijklmnopqrstuvwxyz"'   # 72 characters
BUILD_ARR = 'v = []\n@ i:1..n { v = v $+ i }\n'
BUILD_STR = 'chunk = %s\ns = ""\n@ _c:1..(n / 72) { s = s chunk }\n' % CHUNK
BUILD_DICT = 'd = #()\n@ i:1..n {\n    kk = "k" i\n    d[kk]$~ i\n}\n'


def hot(body):
    return '? k > 0 {\n    @ i:1..k {\n%s\n    }\n}\n' % ''.join('        ' + l + '\n' for l in body.strip().split('\n')).rstrip('\n')


# (name, kind, expected b, first n, largest n, K, program)
OPS = [
 ('arr_append', 'total', 1.0, 20000, 4000000, 0, BUILD_ARR + '>> v$# ¶\n'),
 ('arr_read', 'total', 1.0, 20000, 2000000, 0, BUILD_ARR + 's = 0\n@ i:1..n { s = s + v[i] }\n>> s ¶\n'),
 ('arr_foreach', 'total', 1.0, 20000, 2000000, 0, BUILD_ARR + 's = 0\n@ x:v { s = s + x }\n>> s ¶\n'),
 ('arr_update_each', 'total', 1.0, 2000, 200000, 0, 'v = []\n@ i:1..n { v = v $+ 0 }\n@ i:1..n { v[i]$~ i }\n>> v[n] ¶\n'),
 ('arr_remove_last', 'total', 1.0, 2000, 200000, 0, BUILD_ARR + '@ i:1..n { v = v $-[(n - i + 1)] }\n>> v$# ¶\n'),
 ('map_filter_reduce', 'total', 1.0, 20000, 2000000, 0, BUILD_ARR + 'a = v $> (x -> x * 2)\nb = a $| (x -> x % 3 == 0)\nc = b $< (0, (acc, x) -> acc + x)\n>> c ¶\n'),
 ('sort_builtin', 'total', 1.15, 20000, 2000000, 0, 'v = []\nx = 12345\n@ _i:1..n {\n    x = (x * 1103 + 12345) % 1000003\n    v = v $+ x\n}\nr = v $^+\n>> r[1] ¶\n'),
 ('sort_comparator', 'total', 1.15, 5000, 1000000, 0, 'v = []\nx = 12345\n@ _i:1..n {\n    x = (x * 1103 + 12345) % 1000003\n    v = v $+ x\n}\nr = v $^ (p, q -> p < q)\n>> r[1] ¶\n'),
 ('str_concat', 'total', 1.0, 4000, 256000, 0, 's = ""\n@ i:1..n { s = s "x" }\n>> s$# ¶\n'),
 ('str_iter', 'percall', 1.0, 4608, 294912, 1, BUILD_STR + 'c = 0\n? k > 0 {\n    @ ch:s {\n        ? ch == \'a\' { c = c + 1 }\n    }\n}\n>> c ¶\n'),
 ('str_split', 'percall', 1.0, 20000, 320000, 1, 's = ""\n@ _i:1..(n / 8) { s = s "abc,def," }\nr = 0\n? k > 0 {\n    p = s $/ \',\'\n    r = p$#\n}\n>> r ¶\n'),
 ('str_interp', 'total', 1.0, 20000, 2000000, 0, 'c = 0\n@ i:1..n {\n    t = "{i}"\n    c = c + t$#\n}\n>> c ¶\n'),
 ('dict_insert', 'total', 1.0, 2000, 200000, 0, BUILD_DICT + '>> d["k1"] ¶\n'),
 ('call_overhead', 'total', 1.0, 100000, 4000000, 0, 'f(x) { <~ x + 1 }\ns = 0\n@ i:1..n { s = f(s) }\n>> s ¶\n'),
 ('closure_create_call', 'total', 1.0, 20000, 2000000, 0, 's = 0\n@ i:1..n {\n    g = (x -> x + i)\n    s = s + g(1)\n}\n>> s ¶\n'),
 ('match_range', 'total', 1.0, 100000, 4000000, 0, 'c = 0\n@ i:1..n {\n    c = c + ?? (i % 100) {\n        0..9 => 1\n        10..49 => 2\n        _ => 3\n    }\n}\n>> c ¶\n'),
 ('print_lines', 'total', 1.0, 20000, 400000, 0, '@ i:1..n { >> i ¶ }\n'),
 ('recursion_depth', 'total', 1.0, 1000, 1000000, 0, 'down(m) {\n    ? m == 0 { <~ 0 }\n    <~ 1 + down(m - 1)\n}\n>> down(n) ¶\n'),
 ('arr_update_one', 'percall', 0.0, 20000, 800000, 2000, BUILD_ARR + hot('v[1]$~ i') + '>> v[1] ¶\n'),
 ('arr_slice_small', 'percall', 0.0, 20000, 800000, 2000, BUILD_ARR + hot('t = v$[1..10]') + '>> v$# ¶\n'),
 ('arr_len', 'percall', 0.0, 20000, 800000, 20000, BUILD_ARR + hot('m = v$#') + '>> v$# ¶\n'),
 ('arr_pass_to_function', 'percall', 0.0, 20000, 800000, 5000, 'f(a) { <~ a[1] }\n' + BUILD_ARR + hot('m = f(v)') + '>> v$# ¶\n'),
 ('arr_get_middle', 'percall', 0.0, 20000, 800000, 20000, BUILD_ARR + hot('m = v[(n / 2)]') + '>> v$# ¶\n'),
 ('str_len', 'percall', 0.0, 18432, 294912, 20000, BUILD_STR + hot('m = s$#') + '>> s$# ¶\n'),
 ('str_slice_small', 'percall', 0.0, 18432, 294912, 5000, BUILD_STR + hot('t = s$[1..10]') + '>> s$# ¶\n'),
 ('dict_lookup', 'percall', 0.0, 1000, 8000, 200000, BUILD_DICT + hot('m = d["k1"]') + '>> d["k1"] ¶\n'),
 # Added 2026-10-14: `dict_lookup` reads the key inserted first, which a linear search finds at
 # once (PERF-03). This reads the last one.
 ('dict_lookup_last', 'percall', 0.0, 1000, 8000, 20000, BUILD_DICT + 'last = "k" n\n' + hot('m = d[last]') + '>> d["k1"] ¶\n'),
 ('dict_update_existing', 'percall', 0.0, 1000, 8000, 2000, BUILD_DICT + hot('d["k1"]$~ i') + '>> d["k1"] ¶\n'),
]

# What each curve is fitted in, and below what a point is too small to fit.
FLOORS = {'cpu-ms': 8, 'instructions': 40e6, 'steps': 1000, 'bytes': 100000}
SLACK = 0.35            # b above expected + SLACK is marked `!`


def fit(points, floor):
    """Least-squares slope of log y over log n, from the points at or above
    `floor`; None with fewer than three."""
    pts = [(math.log(n), math.log(y)) for n, y in points if y >= floor]
    if len(pts) < 3:
        return None
    mx, my = sum(p[0] for p in pts) / len(pts), sum(p[1] for p in pts) / len(pts)
    den = sum((p[0] - mx) ** 2 for p in pts)
    return sum((p[0] - mx) * (p[1] - my) for p in pts) / den if den else None


def point(meter, cmd, n, k, kind, startup):
    """→ (time, steps, bytes, time of the run, time subtracted) of the operation alone at size n,
    or a string saying why there is none. A `percall` point subtracts the same
    program with k = 0, in every unit; a `total` point subtracts start-up from
    the time — the counters of an empty program are a few hundred and do not
    move a fit."""
    t, _, out, code = meter(cmd(n, k))
    cnt, _ = counted(cmd(n, k))
    if t is None or cnt is None:
        return 'ERROR exit %s' % code
    if kind == 'percall':
        bt, _, _, _ = meter(cmd(n, 0))
        bc, _ = counted(cmd(n, 0))
        if bt is None or bc is None:
            return 'ERROR in the k = 0 run'
        return (max(t - bt, 0.0), max(cnt['steps'] - bc['steps'], 0), max(cnt['bytes'] - bc['bytes'], 0), t, bt)
    return (max(t - startup, 0.0), cnt['steps'], cnt['bytes'], t, startup)


def probe(meter, cmd, kind, nstart, nmax, kk, startup):
    # calibrate by the clock — it only chooses a size: raise n until the
    # operation itself takes more than ~25 ms of CPU
    n = nstart
    for _ in range(8):
        t, _, _, code = cpu_ms(cmd(n, kk), runs=1)
        if t is None:
            return {'status': 'ERROR exit %d' % code, 'points': [], 'b': {}}
        base = cpu_ms(cmd(n, 0), runs=1)[0] if kind == 'percall' else 0
        if t - (base or 0) >= 25 or n >= nmax:
            break
        n = min(n * 4, nmax)
    pts, status = [], 'OK'
    for mult in (1, 2, 4, 8):
        nn = n * mult
        if nn > nmax * 8:
            break
        p = point(meter, cmd, nn, kk, kind, startup)
        if isinstance(p, str):
            status = p
            break
        pts.append((nn,) + p)
        # stop before a point takes minutes: ~6 s of CPU, or its instructions
        if p[3] > (3e10 if meter.unit == 'instructions' else 6000):
            break
    b = {meter.unit: fit([(q[0], q[1]) for q in pts], FLOORS[meter.unit]),
         'steps': fit([(q[0], q[2]) for q in pts], FLOORS['steps']),
         'bytes': fit([(q[0], q[3]) for q in pts], FLOORS['bytes'])}
    return {'status': status, 'points': pts, 'b': b}


def verdict(res, unit, expect):
    """`!` the time grows faster than expected; `blind` when neither counter
    does — a scan inside one instruction, which `cost/` can only hold by its
    clock — and `counted` when one does, so a `cost/` case can hold it exactly.

    `noisy` when the unit is the clock and either the curve does not rise
    point by point or a point's net is under a tenth of what was subtracted
    from it: a `percall` net of tens of milliseconds taken from a run of
    seconds is the difference of two noisy runs. On 2026-10-14 updating the
    first key of a dictionary fitted b = 1.08 and then 1.18 that way, while a
    timer inside the program read 2-3 ms at every size. It is reported, and it
    does not fail the run: instructions, or `gap.py`'s timer, decide it."""
    bt = res['b'].get(unit)
    if bt is None or bt <= expect + SLACK:
        return ''
    ts = [p[1] for p in res['points']]
    if unit == 'cpu-ms' and (any(b < a * 0.9 for a, b in zip(ts, ts[1:]))
                             or any(p[1] < 0.1 * p[5] for p in res['points'])):
        return 'noisy'
    seen = [c for c in ('steps', 'bytes') if res['b'].get(c) is not None and res['b'][c] > expect + SLACK]
    return 'counted:' + '+'.join(seen) if seen else 'blind'


def main():
    ap = argparse.ArgumentParser(description=__doc__.split('\n\n')[0])
    ap.add_argument('--only', default='', help='comma-separated operation names')
    ap.add_argument('--json', default='', metavar='PATH', help='also write the results here')
    ap.add_argument('--no-tw', action='store_true', help='measure the VM only')
    ap.add_argument('--runs', type=int, default=3, help='runs per median of the time unit (default 3)')
    ap.add_argument('--clock', action='store_true', help='use CPU time even where perf is available')
    a = ap.parse_args()
    if a.runs < 1:
        ap.error('--runs must be at least 1')
    new, old = os.environ.get('ZYMBOL_BIN', 'zymbol'), os.environ.get('ZYMBOL_OLD', '')
    try:
        ver = subprocess.run([new, '--version'], capture_output=True, text=True).stdout.strip()
    except FileNotFoundError:
        print('scaling.py: no `%s` — install it, or set ZYMBOL_BIN to a build' % new, file=sys.stderr)
        return 2
    if a.only:
        unknown = [w for w in a.only.split(',') if w not in [o[0] for o in OPS]]
        if unknown:
            ap.error('no such operation: ' + ', '.join(unknown))
    meter = Meter(force_clock=a.clock, runs=a.runs)
    ops = [o for o in OPS if not a.only or o[0] in a.only.split(',')]
    # Every engine by name: since v0.0.11 a bare `run` is the VM.
    engines = [('VM', new, '--vm')] + ([] if a.no_tw else [('TW', new, '--tw')]) + \
              ([('VM-old', old, '--vm')] if old else [])
    print('%s (%s) | exponent b of y ~ n^b | 1.0 = linear, 2.0 = quadratic' % (ver, new))
    print(meter.header())
    print('each cell: b in that unit, then b in `--count` steps and bytes (exact, one run)\n')
    print('%-22s %-7s %6s | %s' % ('operation', 'kind', 'expect', ' | '.join('%-38s' % e[0] for e in engines)))
    results = []
    with tempfile.TemporaryDirectory(prefix='zyscale-') as tmp:
        empty = os.path.join(tmp, 'empty.zy')
        open(empty, 'w', encoding='utf-8').write('>> "" ¶\n')
        startup = {label: meter([binary, 'run', flag, empty])[0] or 0 for label, binary, flag in engines}
        for name, kind, expect, nstart, nmax, kk, src in ops:
            path = os.path.join(tmp, name + '.zy')
            open(path, 'w', encoding='utf-8').write(HEAD + src)
            row, cells = {'op': name, 'kind': kind, 'expect': expect}, []
            for label, binary, flag in engines:
                cmd = lambda n, k, b=binary, f=flag: [b, 'run', f, path, str(n), str(k)]
                res = probe(meter, cmd, kind, nstart, nmax, kk, startup[label])
                res['verdict'] = verdict(res, meter.unit, expect)
                row[label] = res
                f = lambda v: '   ?' if v is None else '%4.2f' % v
                b = res['b']
                last = res['points'][-1][0] if res['points'] else 0
                mark = {'': ' ', 'noisy': '~'}.get(res['verdict'], '!')
                cell = 'b=%s%s s=%s y=%s n=%d' % (f(b.get(meter.unit)), mark,
                                                  f(b.get('steps')), f(b.get('bytes')), last)
                if res['status'] != 'OK':
                    cell += ' ' + res['status'][:12]
                cells.append('%-38s' % cell)
            results.append(row)
            print('%-22s %-7s %6.2f | %s' % (name, kind, expect, ' | '.join(cells)), flush=True)
    print('\nb = the time unit, s = steps, y = bytes. `!` marks b above the expected value + %.2f; '
          '`~` the same on a clock curve that does not rise point by point; `?` = too small to fit.' % SLACK)
    judged = [(r['op'], l, r[l]['verdict']) for r in results for l in ('VM', 'TW')
              if isinstance(r.get(l), dict) and r[l]['verdict']]
    flagged = [j for j in judged if j[2] != 'noisy']
    noisy = ['%s %s' % (op, l) for op, l, v in judged if v == 'noisy']
    if noisy:
        print('Too noisy to judge by the clock (not counted as failures): ' + ', '.join(noisy))
    if flagged:
        print('Growing faster than expected:')
        for op, label, v in flagged:
            how = ('`--count` does not see it: a scan inside one instruction; cost/ can hold it by the clock only'
                   if v == 'blind' else '`--count` sees it in %s: cost/ can hold it exactly' % v.split(':')[1])
            print('  %-22s %-3s %s' % (op, label, how))
    else:
        print('Growing faster than expected: none')
    if a.json:
        with open(a.json, 'w', encoding='utf-8') as fh:
            json.dump({'zymbol': ver, 'binary': new, 'unit': meter.unit, 'unit_reason': meter.reason,
                       'runs': meter.runs, 'startup': startup, 'results': results}, fh, indent=1, ensure_ascii=False)
    return 1 if flagged else 0


if __name__ == '__main__':
    sys.exit(main())
