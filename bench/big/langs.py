#!/usr/bin/env python3
"""ZyLangs — the sixteen programs of bench/big against other languages.

`run.py` asks one question: what does a whole program cost in Zymbol, against
Python? This asks the same of more neighbours. Every program has a twin per
language in py/, pl/, php/, lua/, rb/, js/ and jl/, written as the Python twin is written —
same algorithm, same shape, same printed line — and that line is checked
against Python's before any figure is kept: a twin that answers something
else is a different program.

Two kinds of neighbour, and the report keeps them apart:

  * interpreters, as Zymbol is: Python (CPython), Perl, PHP, Lua (PUC) and
    Ruby (CRuby) — PHP's opcache JIT is off on the command line by default,
    and Ruby's YJIT needs `--yjit`, so both run here as interpreters;
  * JIT compilers, which turn the program into machine code: JavaScript
    (Node, V8) and Julia. They are expected to win; they are here as the
    reference of what compiling buys.

Julia's twins put their code in a `main()` function: in Julia a global is
untyped, and measuring that would measure a use nobody writes.

Each figure is the median of `--runs` processes, start-up included, in
elapsed (wall-clock) time and in CPU time — user + system, as the kernel
accounts the child (`wait4`), which needs no privilege — and, where
`perf_event_paranoid` allows, in user-space instructions. Elapsed time leads:
a runtime that compiles on other threads (Julia) spends CPU time no one waits
for. Run it on a machine that is otherwise idle. The start-up of each runtime alone — an empty program — is
measured too, because for the short programs it is most of the figure.

    python3 langs.py --json out.json          # ZYMBOL_BIN chooses the binary
    python3 langs.py --only fib_rec,tak --runs 3
"""
import argparse
import json
import os
import platform
import shutil
import statistics
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
OLD = os.environ.get('ZYMBOL_OLD')

LANGS = [
    # key, label, kind, extension, command
    ('zymbol', 'Zymbol (VM)', 'interpreter', 'zy', lambda zy, f: [zy, 'run', f]),
    # The other engines of Zymbol, so a reader can fix any of them as the
    # reference: the tree-walker of this build, and both engines of an older
    # one (ZYMBOL_OLD) — v0.0.10 ran the tree-walker by default.
    ('zymbol_tw', 'Zymbol (tree-walker)', 'zymbol-engine', 'zy', lambda zy, f: [zy, 'run', '--tw', f]),
    ('zymbol_old', 'Zymbol, older build (VM)', 'zymbol-engine', 'zy', lambda zy, f: [OLD, 'run', '--vm', f]),
    ('zymbol_old_tw', 'Zymbol, older build (tree-walker)', 'zymbol-engine', 'zy', lambda zy, f: [OLD, 'run', '--tw', f]),
    ('python', 'Python (CPython)', 'interpreter', 'py', lambda zy, f: ['python3', f]),
    ('perl', 'Perl', 'interpreter', 'pl', lambda zy, f: ['perl', f]),
    ('php', 'PHP', 'interpreter', 'php', lambda zy, f: ['php', f]),
    ('lua', 'Lua', 'interpreter', 'lua', lambda zy, f: ['lua', f]),
    ('ruby', 'Ruby', 'interpreter', 'rb', lambda zy, f: ['ruby', f]),
    ('node', 'JavaScript (Node, V8)', 'jit', 'js', lambda zy, f: ['node', f]),
    ('julia', 'Julia', 'jit', 'jl', lambda zy, f: ['julia', '--startup-file=no', f]),
]

EMPTY = {'zy': '', 'py': '', 'pl': '', 'php': '', 'lua': '', 'rb': '', 'js': '', 'jl': ''}


def version(cmd):
    try:
        out = subprocess.run(cmd, capture_output=True, text=True, timeout=60)
        return (out.stdout or out.stderr).strip().splitlines()[0]
    except (OSError, subprocess.SubprocessError, IndexError):
        return '?'


def perf_counts(cmd, events):
    """One run under `perf stat`: {event: value}. LC_ALL=C — a locale that
    writes decimals with a comma breaks perf's CSV."""
    r = subprocess.run(['env', 'LC_ALL=C', 'perf', 'stat', '-x,', '-e', ','.join(events)] + cmd,
                       capture_output=True, text=True)
    got = {}
    for line in r.stderr.splitlines():
        f = line.split(',')
        if len(f) > 2:
            for e in events:
                if f[2].startswith(e.split(':')[0]) and f[0] not in ('<not counted>', '<not supported>', ''):
                    got[e] = float(f[0])
    return got


def wall_and_cpu_ms(cmd):
    """One run: elapsed (wall-clock) time, and CPU time — user + system from
    the kernel's accounting of the child (`wait4`), which needs no privilege.

    Both, because they part ways for a runtime that works on several threads:
    Julia compiles on other cores while it starts, and its CPU time was three
    times its elapsed time (fib_rec: 648 ms of CPU in 223 ms). Elapsed time is
    what whoever runs the program waits, and the figure the report leads with;
    for a single-threaded interpreter the two agree within a few percent."""
    import time
    t0 = time.perf_counter()
    p = subprocess.Popen(cmd, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    _pid, _status, ru = os.wait4(p.pid, 0)
    return (time.perf_counter() - t0) * 1000.0, (ru.ru_utime + ru.ru_stime) * 1000.0


def perf_works():
    r = subprocess.run(['env', 'LC_ALL=C', 'perf', 'stat', '-x,', '-e', 'instructions:u', 'true'],
                       capture_output=True, text=True)
    return r.returncode == 0 and 'instructions' in r.stderr


def measure(cmd, runs, events):
    """Median CPU time in ms, and median user-space instructions when perf is
    allowed to count them (None otherwise)."""
    runs_ = [wall_and_cpu_ms(cmd) for _ in range(runs)]
    times = [c for _w, c in runs_]
    walls = [w for w, _c in runs_]
    ins = []
    if 'instructions:u' in events:
        for _ in range(runs):
            got = perf_counts(cmd, ['instructions:u'])
            if 'instructions:u' in got:
                ins.append(got['instructions:u'])
    return {'task-clock': statistics.median(times), 'wall': statistics.median(walls),
            'instructions:u': statistics.median(ins) if ins else None}


def main():
    ap = argparse.ArgumentParser(description=__doc__.split('\n')[0])
    ap.add_argument('--runs', type=int, default=5)
    ap.add_argument('--only', help='comma-separated program names')
    ap.add_argument('--json', help='also write the results here')
    a = ap.parse_args()

    zy = os.environ.get('ZYMBOL_BIN', 'zymbol')
    if not shutil.which(zy) and not os.path.exists(zy):
        sys.exit('langs.py: no `%s` — set ZYMBOL_BIN to a build' % zy)
    # CPU time always; instructions only where perf may count them.
    events = ['task-clock'] + (['instructions:u'] if shutil.which('perf') and perf_works() else [])
    if len(events) == 1:
        print('langs.py: perf cannot count here (perf_event_paranoid?) — CPU time only', file=sys.stderr)
    langs = [l for l in LANGS
             if l[0] in ('zymbol', 'zymbol_tw')
             or (l[0].startswith('zymbol_old') and OLD and os.path.exists(OLD))
             or (not l[0].startswith('zymbol') and shutil.which(l[4](zy, 'x')[0]))]
    progs = sorted(f[:-3] for f in os.listdir(os.path.join(HERE, 'zy')) if f.endswith('.zy'))
    if a.only:
        wanted = set(a.only.split(','))
        progs = [p for p in progs if p in wanted]

    versions = {
        'zymbol': version([zy, '--version']),
        'zymbol_tw': version([zy, '--version']),
        'zymbol_old': version([OLD, '--version']) if OLD else '?',
        'zymbol_old_tw': version([OLD, '--version']) if OLD else '?',
        'python': version(['python3', '--version']),
        'perl': version(['perl', '-e', 'print "perl $^V\\n"']),
        'php': version(['php', '-v']),
        'lua': version(['lua', '-v']),
        'ruby': version(['ruby', '-v']),
        'node': version(['node', '--version']),
        'julia': version(['julia', '--version']),
    }
    cpu = '?'
    try:
        with open('/proc/cpuinfo') as fh:
            cpu = next(l.split(':', 1)[1].strip() for l in fh if l.startswith('model name'))
    except (OSError, StopIteration):
        pass

    # Start-up alone: an empty program in each language.
    startup = {}
    with tempfile.TemporaryDirectory() as tmp:
        for key, _label, _kind, ext, cmd in langs:
            f = os.path.join(tmp, 'empty.' + ext)
            with open(f, 'w') as fh:
                fh.write(EMPTY[ext])
            startup[key] = measure(cmd(zy, f), a.runs, events)

    rows = []
    for p in progs:
        ref = subprocess.run(['python3', os.path.join(HERE, 'py', p + '.py')],
                             capture_output=True, text=True).stdout.strip()
        row = {'program': p, 'output': ref, 'langs': {}}
        for key, _label, _kind, ext, cmd in langs:
            f = os.path.join(HERE, ext, '%s.%s' % (p, ext))
            if not os.path.exists(f):
                continue
            c = cmd(zy, f)
            out = subprocess.run(c, capture_output=True, text=True).stdout.strip()
            ok = out == ref
            m = measure(c, a.runs, events) if ok else {'task-clock': None, 'wall': None, 'instructions:u': None}
            row['langs'][key] = {'ok': ok, 'wall_ms': m['wall'], 'ms': m['task-clock'],
                                 'instructions': m['instructions:u']}
        rows.append(row)
        line = '  '.join('%s %s' % (k, ('%6.0f ms' % v['wall_ms']) if v['ok'] else 'WRONG')
                         for k, v in row['langs'].items())
        print('%-20s %s' % (p, line), flush=True)

    print('\nstart-up (empty program, elapsed): ' + '  '.join(
        '%s %.0f ms' % (k, v['wall']) for k, v in startup.items() if v['wall']))
    wrong = [(r['program'], k) for r in rows for k, v in r['langs'].items() if not v['ok']]
    print('%d of %d twins agree with Python' % (
        sum(len(r['langs']) for r in rows) - len(wrong), sum(len(r['langs']) for r in rows)))

    if a.json:
        doc = {
            'what': 'bench/big, each program as a twin per language: elapsed time, CPU time and instructions per process',
            'runs': a.runs,
            'cpu': cpu,
            'os': '%s %s' % (platform.system(), platform.release()),
            'versions': versions,
            'langs': [{'key': k, 'label': l, 'kind': kind} for k, l, kind, _e, _c in langs],
            'startup': {k: {'wall_ms': v['wall'], 'ms': v['task-clock'], 'instructions': v['instructions:u']}
                        for k, v in startup.items()},
            'rows': rows,
        }
        with open(a.json, 'w') as fh:
            json.dump(doc, fh, indent=1, ensure_ascii=False)
    return 1 if wrong else 0


if __name__ == '__main__':
    sys.exit(main())
