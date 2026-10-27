#!/usr/bin/env python3
"""ZyAB — two builds of Zymbol on the sixteen programs, run in turn.

Comparing two runs of `langs.py` made on different days measures the machine
as well as the change: on 2026-10-20, against the run of 2026-10-18, the same
v0.0.10 binary came out 2 % faster and the other languages 5 to 10 % faster,
and three programs moved by more than the change being looked for. This asks
the narrower question the other way: both binaries, built with the same cargo
command, each program run once by one and once by the other, over and over, in
the same minutes. Whatever the machine does, it does to both.

For every program and engine it records the median CPU time (user + system of
the child, which needs no privilege) of each binary, the steps `--count`
reports — exact, so equal steps mean the same work and a difference in time is
how the code was laid out, not what it does — and whether both printed the
same thing.

    python3 ab.py --a old/zymbol --a-label 7ef269c --b new/zymbol --b-label 52ad7d3 \\
                  --runs 7 --json ab.json
"""
import argparse
import glob
import json
import os
import platform
import resource
import statistics
import subprocess

HERE = os.path.dirname(os.path.abspath(__file__))
# Each engine by its flag: a bare `zymbol run` is the VM since v0.0.11 and the
# tree-walker before it, so with a v0.0.10 build as --a an empty flag measured
# the wrong engine on one side.
ENGINES = {'vm': ['--vm'], 'tw': ['--tw']}


def cpu_ms(cmd):
    """CPU time of one child, and what it printed."""
    before = resource.getrusage(resource.RUSAGE_CHILDREN)
    out = subprocess.run(cmd, capture_output=True, text=True)
    after = resource.getrusage(resource.RUSAGE_CHILDREN)
    if out.returncode != 0:
        raise SystemExit('ab.py: %s exited %d: %s' % (' '.join(cmd), out.returncode, out.stderr[-300:]))
    t = (after.ru_utime - before.ru_utime + after.ru_stime - before.ru_stime) * 1000
    return t, out.stdout


def steps(cmd):
    out = subprocess.run(cmd[:2] + ['--count'] + cmd[2:], capture_output=True, text=True)
    for line in out.stderr.splitlines():
        if 'steps=' in line:
            return int(line.split('steps=')[1].split()[0])
    return None


def main():
    ap = argparse.ArgumentParser(description=__doc__.split('\n')[0])
    ap.add_argument('--a', required=True, help='the earlier build')
    ap.add_argument('--b', required=True, help='the later build')
    ap.add_argument('--a-label', required=True)
    ap.add_argument('--b-label', required=True)
    ap.add_argument('--runs', type=int, default=7)
    ap.add_argument('--engines', default='vm,tw')
    ap.add_argument('--only', default='', help='comma-separated program names')
    ap.add_argument('--json', required=True)
    a = ap.parse_args()
    progs = sorted(os.path.basename(f)[:-3] for f in glob.glob(os.path.join(HERE, 'zy', '*.zy')))
    if a.only:
        progs = [p for p in progs if p in a.only.split(',')]
    rows = []
    for eng in a.engines.split(','):
        for p in progs:
            f = os.path.join(HERE, 'zy', p + '.zy')
            ca = [a.a, 'run'] + ENGINES[eng] + [f]
            cb = [a.b, 'run'] + ENGINES[eng] + [f]
            ta, tb, oa, ob = [], [], None, None
            for _ in range(a.runs):
                t, oa = cpu_ms(ca)
                ta.append(t)
                t, ob = cpu_ms(cb)
                tb.append(t)
            row = {'program': p, 'engine': eng,
                   'a_ms': statistics.median(ta), 'b_ms': statistics.median(tb),
                   'a_steps': steps(ca), 'b_steps': steps(cb), 'same_output': oa == ob}
            rows.append(row)
            print('%-3s %-20s %8.1f %8.1f  %5.3f  steps %s%s' % (
                eng, p, row['a_ms'], row['b_ms'], row['b_ms'] / row['a_ms'],
                'same' if row['a_steps'] == row['b_steps'] else '%s -> %s' % (row['a_steps'], row['b_steps']),
                '' if row['same_output'] else '  OUTPUT DIFFERS'), flush=True)
    cpu = ''
    try:
        cpu = next(l.split(':', 1)[1].strip() for l in open('/proc/cpuinfo') if l.startswith('model name'))
    except (OSError, StopIteration):
        pass
    json.dump({'what': 'two builds of Zymbol, the same programs run in turn, CPU time',
               'a': {'label': a.a_label}, 'b': {'label': a.b_label}, 'runs': a.runs,
               'cpu': cpu, 'os': '%s %s' % (platform.system(), platform.release()), 'rows': rows},
              open(a.json, 'w'), indent=1)


if __name__ == '__main__':
    main()
