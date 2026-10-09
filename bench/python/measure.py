#!/usr/bin/env python3
"""ZyBench — the bench/ programs against their Python ports.

Each port in this directory does the work of one program in bench/ and prints
the same lines: a label that carries the result, then the elapsed time. So a
port is two things at once — an ORACLE for the result, and a REFERENCE for the
time. The result comes first: a test whose label differs from Zymbol's, in any
run, is reported as a disagreement and its time is not compared.

  python3 measure.py                              # VM, general group, median of 3
  python3 measure.py --engine tw --group text --runs 5
  python3 measure.py --group all --json out.json

ZYMBOL_BIN chooses the binary (default: `zymbol` on PATH), as in bench_gate.sh.
Exit 0 when every result agrees, 1 when one does not, 2 on a usage error.
"""
import argparse, json, os, re, statistics, subprocess, sys

HERE = os.path.dirname(os.path.abspath(__file__))
BENCH = os.path.dirname(HERE)

# (port, Zymbol program relative to bench/)
GROUPS = {
    'general': [('bench_recursion', 'bench_recursion.zy'),
                ('bench_collections', 'bench_collections.zy'),
                ('bench_match', 'bench_match.zy'),
                ('bench_numeric', 'stress_v2/bench_numeric.zy'),
                ('bench_hof', 'stress_v2/bench_hof.zy')],
    'text':    [('bench_strings', 'bench_strings.zy'),
                ('bench_strings_modify', 'bench_strings_modify.zy'),
                ('bench_strings_stress', 'bench_strings_stress.zy'),
                ('bench_text', 'stress_v2/bench_text.zy')],
}
GROUPS['all'] = GROUPS['general'] + GROUPS['text']

# Below this, either side's time is timer noise: a ratio against it is a bound.
NOISE_MS = 10.0

LINE = re.compile(r'^(.*?)\s+\((\d+\.\d+)s\)\s*$')


def parse(out):
    """[(label, ms)] for every timed line; the label is normalised so that the
    two languages' spacing around `:` and `=` does not count as a difference."""
    res = []
    for raw in out.splitlines():
        line = re.sub(r'\x1b\[[0-9;]*m', '', raw)
        m = LINE.match(line)
        if m and not line.startswith('==='):
            label = re.sub(r'[\s:=]+', ' ', m.group(1)).strip().lower()
            res.append((label, float(m.group(2)) * 1000))
    return res


def run(cmd, cwd):
    r = subprocess.run(cmd, cwd=cwd, capture_output=True, timeout=280,
                       stdin=subprocess.DEVNULL)
    return r.returncode, parse(r.stdout.decode('utf-8', 'replace')), r.stderr.decode('utf-8', 'replace')


def measure(cmd, cwd, runs, who):
    """Median ms per line over `runs`, and the labels — which must not vary."""
    labels, times = None, []
    for _ in range(runs):
        rc, lines, err = run(cmd, cwd)
        if rc != 0 or not lines:
            return None, '%s: exit %d, %d timed lines\n%s' % (who, rc, len(lines), err.strip()[-400:])
        if labels is None:
            labels = [l for l, _ in lines]
        elif [l for l, _ in lines] != labels:
            return None, '%s: the result changed between runs' % who
        times.append([ms for _, ms in lines])
    return (labels, [statistics.median(col) for col in zip(*times)]), None


def main():
    ap = argparse.ArgumentParser(description=__doc__.split('\n\n')[0])
    ap.add_argument('--engine', choices=['vm', 'tw'], default='vm')
    ap.add_argument('--group', choices=sorted(GROUPS), default='general')
    ap.add_argument('--runs', type=int, default=3)
    ap.add_argument('--json', metavar='PATH', help='also write the results here')
    a = ap.parse_args()
    if a.runs < 1:
        ap.error('--runs must be at least 1')

    zymbol = os.environ.get('ZYMBOL_BIN', 'zymbol')
    try:
        zver = subprocess.run([zymbol, '--version'], capture_output=True, text=True).stdout.strip()
    except FileNotFoundError:
        print('measure.py: no `%s` — install it, or set ZYMBOL_BIN to a build' % zymbol, file=sys.stderr)
        return 2
    pyver = 'Python %d.%d.%d' % sys.version_info[:3]
    print('%s (%s, engine %s) against %s — median of %d' % (zver, zymbol, a.engine, pyver, a.runs))

    rows, problems = [], []
    for port, zy in GROUPS[a.group]:
        zpath = os.path.join(BENCH, zy)
        py, err_py = measure([sys.executable, port + '.py'], HERE, a.runs, port + '.py')
        zcmd = [zymbol, 'run'] + (['--vm'] if a.engine == 'vm' else []) + [zpath]
        zr, err_zy = measure(zcmd, os.path.dirname(zpath), a.runs, zy)
        for e in (err_py, err_zy):
            if e:
                problems.append(e)
        if not py or not zr:
            continue
        (pl, pt), (zl, zt) = py, zr
        if len(pl) != len(zl):
            problems.append('%s: %d lines in Python, %d in Zymbol' % (port, len(pl), len(zl)))
            continue
        for p_label, p_ms, z_label, z_ms in zip(pl, pt, zl, zt):
            rows.append({'program': port, 'test': z_label, 'agree': p_label == z_label,
                         'python_label': p_label, 'python_ms': p_ms, 'zymbol_ms': z_ms})

    print()
    print('%-22s %-46s %10s %10s %8s' % ('program', 'test (its result)', 'Python ms', 'Zymbol ms', 'Zy/Py'))
    for r in rows:
        if not r['agree']:
            print('%-22s %-46s %s' % (r['program'], r['test'][:46], 'RESULT DIFFERS'))
            print('%-22s %-46s' % ('', '  python: ' + r['python_label'][:38]))
            continue
        noisy = r['python_ms'] < NOISE_MS or r['zymbol_ms'] < NOISE_MS
        ratio = r['zymbol_ms'] / r['python_ms'] if r['python_ms'] > 0 else float('inf')
        shown = ('~%.2f' if noisy else '%.2f') % ratio if ratio != float('inf') else 'bound'
        print('%-22s %-46s %10.0f %10.0f %8s' % (r['program'], r['test'][:46], r['python_ms'], r['zymbol_ms'], shown))

    agree = sum(r['agree'] for r in rows)
    print()
    print('%d of %d results agree with the Python oracle' % (agree, len(rows)), end='')
    print('; ~ marks a ratio where one side ran under %d ms (a bound, not a value)' % NOISE_MS)
    for p in problems:
        print('  ✗ ' + p)

    if a.json:
        with open(a.json, 'w', encoding='utf-8') as f:
            json.dump({'zymbol': zver, 'binary': zymbol, 'engine': a.engine, 'python': pyver,
                       'runs': a.runs, 'group': a.group, 'tests': rows, 'problems': problems},
                      f, ensure_ascii=False, indent=1)
    return 0 if rows and agree == len(rows) and not problems else 1


if __name__ == '__main__':
    sys.exit(main())
