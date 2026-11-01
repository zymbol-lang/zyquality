#!/usr/bin/env python3
"""ZyBigBench — sixteen long Zymbol programs against their Python twins.

Every program in zy/ has a twin in py/ that prints exactly the same thing. The
output is compared FIRST: a program whose output differs from Python's is
reported as DIFFERS and stays out of every summary.

Two instruments (see instruments.py):

  · the cost of each program against its twin, in instructions:u (perf, median
    of 7) — or in CPU ms where perf is not allowed, said on the first line —
    minus what an empty program costs in each interpreter;
  · what Zymbol did, in `zymbol run --count`'s exact units: steps, allocs,
    bytes and copied. One run; the same on every machine.

  python3 run.py                                   # VM
  python3 run.py --engine tw --only fib_rec,tak
  ZYMBOL_OLD=/path/to/other/zymbol python3 run.py --json out.json

ZYMBOL_BIN chooses the binary (default: `zymbol` on PATH), as in bench_gate.sh;
ZYMBOL_OLD adds a second binary, same engine, for a before/after column — and a
before/after in `--count` units is exact, so it is the one to quote.
Exit 0 when every output agrees, 1 when one does not, 2 on a usage error.
"""
import argparse, json, math, os, re, subprocess, sys, tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)                     # `python3 -I` leaves the script's directory out
from instruments import Meter, counted       # noqa: E402

ZY, PY = os.path.join(HERE, 'zy'), os.path.join(HERE, 'py')
LIMIT = 300                    # seconds per run
NEW_ONLY = {'sort_cmp_300k'}   # with the bubble sort GLB-108 replaced it takes hours
ANSI = re.compile(r'\x1b\[[0-9;]*m')


def clean(out):
    return ANSI.sub('', out or '').strip()


def gmean(xs):
    xs = [x for x in xs if x and x > 0]
    return math.exp(sum(math.log(x) for x in xs) / len(xs)) if xs else float('nan')


def human(n):
    for unit, size in (('G', 1e9), ('M', 1e6), ('k', 1e3)):
        if n >= size:
            return '%.1f%s' % (n / size, unit)
    return str(n)


def main():
    ap = argparse.ArgumentParser(description=__doc__.split('\n\n')[0])
    ap.add_argument('--engine', choices=['vm', 'tw'], default='vm')
    ap.add_argument('--runs', type=int, help='runs per median (default 7 with perf, 5 with the clock)')
    ap.add_argument('--clock', action='store_true', help='use CPU time even where perf is available')
    ap.add_argument('--only', default='', help='comma-separated program names')
    ap.add_argument('--json', default='', metavar='PATH', help='also write the results here')
    a = ap.parse_args()
    if a.runs is not None and a.runs < 1:
        ap.error('--runs must be at least 1')
    new = os.environ.get('ZYMBOL_BIN', 'zymbol')
    old = os.environ.get('ZYMBOL_OLD', '')
    try:
        ver = subprocess.run([new, '--version'], capture_output=True, text=True).stdout.strip()
    except FileNotFoundError:
        print('run.py: no `%s` — install it, or set ZYMBOL_BIN to a build' % new, file=sys.stderr)
        return 2
    meter = Meter(force_clock=a.clock, runs=a.runs)
    # The engine by name: since v0.0.11 a bare `run` is the VM.
    zrun = lambda binary, path: [binary, 'run', '--' + a.engine, path]
    names = sorted(f[:-3] for f in os.listdir(ZY) if f.endswith('.zy'))
    if a.only:
        wanted = a.only.split(',')
        unknown = [w for w in wanted if w not in names]
        if unknown:
            ap.error('no such program: ' + ', '.join(unknown))
        names = [n for n in names if n in wanted]

    with tempfile.TemporaryDirectory(prefix='zybigbench-') as tmp:
        ezy, epy = os.path.join(tmp, 'empty.zy'), os.path.join(tmp, 'empty.py')
        open(ezy, 'w', encoding='utf-8').write('>> "" ¶\n')
        open(epy, 'w', encoding='utf-8').write('print("")\n')
        start = {'py': meter([sys.executable, epy], tmp)[0], 'new': meter(zrun(new, ezy), tmp)[0]}
        if old:
            start['old'] = meter(zrun(old, ezy), tmp)[0]

    print('%s (%s, engine %s) | Python %s' % (ver, new, a.engine, sys.version.split()[0]))
    print(meter.header())
    print('empty program, subtracted: Python %s | Zymbol %s%s' % (
        meter.fmt(start['py']), meter.fmt(start['new']), (' | old %s' % meter.fmt(start['old'])) if old else ''))
    print('counters: `zymbol run --count`, one run, exact\n')
    print('%-20s %9s %9s %7s | %9s %9s %9s %7s | %s' % (
        'program', 'Python', 'Zymbol', 'Zy/Py', 'steps', 'allocs', 'bytes', 'copied', ''))

    rows = []
    for n in names:
        row = {'program': n, 'unit': meter.unit}
        py_v, _, py_out, py_c = meter([sys.executable, n + '.py'], PY, LIMIT)
        zy_v, _, zy_out, zy_c = meter(zrun(new, n + '.zy'), ZY, LIMIT)
        cnt, _ = counted(zrun(new, n + '.zy'), ZY, LIMIT)
        row.update(py=py_v - start['py'] if py_v is not None else None,
                   new=zy_v - start['new'] if zy_v is not None else None,
                   count=cnt, output=clean(zy_out)[:70])
        row['agree'] = py_c == 0 and zy_c == 0 and clean(py_out) == clean(zy_out)
        if old and n not in NEW_ONLY:
            od_v, _, od_out, od_c = meter(zrun(old, n + '.zy'), ZY, LIMIT)
            row['old'] = od_v - start['old'] if od_v is not None else None
            row['old_count'], _ = counted(zrun(old, n + '.zy'), ZY, LIMIT)
            row['old_agree'] = od_c == 0 and clean(od_out) == clean(py_out)
        rows.append(row)
        # A ratio against a side that is mostly start-up is a bound, not a value.
        floor = 5e6 if meter.unit == 'instructions' else 5
        ratio = ('%7.2f' % (row['new'] / row['py'])) if (row['new'] and row['py'] and row['py'] >= floor) else '      ~'
        c = cnt or {}
        print('%-20s %9s %9s %s | %9s %9s %9s %7s | %s' % (
            n, meter.fmt(row['py']), meter.fmt(row['new']), ratio,
            human(c['steps']) if cnt else '—', human(c['allocs']) if cnt else '—',
            human(c['bytes']) if cnt else '—', human(c['copied']) if cnt else '—',
            'OK' if row['agree'] else 'DIFFERS (%s)' % ('exit %d' % zy_c if zy_c else 'other output')), flush=True)

    agree = sum(1 for x in rows if x['agree'])
    floor = 50e6 if meter.unit == 'instructions' else 50
    ok = [x for x in rows if x['agree'] and x['py'] and x['new'] and x['py'] >= floor]
    print('\n%d of %d programs agree with Python.' % (agree, len(rows)))
    if ok:
        print('Programs with >= %s %s net in Python (%d): geometric mean Zymbol/Python = %.2f, in %s' % (
            meter.fmt(floor), meter.unit, len(ok), gmean([x['new'] / x['py'] for x in ok]), meter.unit))
        print('  cheaper than Python: %s' % (', '.join(x['program'] for x in ok if x['new'] < x['py']) or '—'))
        print('  dearer than Python:  %s' % (', '.join(x['program'] for x in ok if x['new'] >= x['py']) or '—'))
    if old:
        both = [x for x in rows if x['agree'] and x.get('old_agree') and x.get('count') and x.get('old_count')]
        if both:
            print('new/old over %d programs, geometric mean (under 1 is cheaper): steps %.3f, bytes %.3f, %s %.3f' % (
                len(both), gmean([x['count']['steps'] / x['old_count']['steps'] for x in both]),
                gmean([x['count']['bytes'] / x['old_count']['bytes'] for x in both]), meter.unit,
                gmean([x['new'] / x['old'] for x in both if x['new'] and x.get('old')])))
    if a.json:
        with open(a.json, 'w', encoding='utf-8') as fh:
            json.dump({'zymbol': ver, 'binary': new, 'engine': a.engine, 'python': sys.version.split()[0],
                       'unit': meter.unit, 'unit_reason': meter.reason, 'runs': meter.runs,
                       'startup': start, 'rows': rows}, fh, indent=1, ensure_ascii=False)
    return 0 if rows and agree == len(rows) else 1


if __name__ == '__main__':
    sys.exit(main())
