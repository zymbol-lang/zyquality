"""The project's two instruments, for the three runners in this directory.

  counted       `zymbol run --count`: steps, calls, allocs, bytes, copied.
                Exact — the same program gives the same numbers on every run, on
                every machine, whatever else the machine is doing — so ONE run
                answers. It is what `cost/` asserts its growth ratios in.
                Blind to a scan INSIDE one instruction: `s$#` over a long string
                is one step whatever the length.

  instructions  `perf stat -e instructions:u`, the median of several runs: the
                unit `ZyDDT/HALLAZGOS` and `interpreter/ARCHITECTURE.md` quote
                costs in. It sees everything the process executes, Python
                included, which `--count` cannot. It needs
                `kernel.perf_event_paranoid` at 2 or lower; on a machine that
                does not allow it, the runners fall back to CPU time and say so
                on their first line — a clock figure is never printed under an
                instruction heading.

Not a script: the runners import it from their own directory.
"""
import os, re, shutil, statistics, subprocess, tempfile

COUNT_LINE = re.compile(r'^count  (.+)$', re.MULTILINE)
COUNTERS = ('steps', 'calls', 'allocs', 'bytes', 'copied')


def counted(cmd, cwd=None, timeout=300):
    """→ (counters, stdout) for ONE run of `zymbol run [--vm|--tw] FILE …`,
    with `--count` put after `run`. None for the counters if the run failed."""
    assert cmd[1] == 'run', cmd
    r = subprocess.run(cmd[:2] + ['--count'] + cmd[2:], cwd=cwd, capture_output=True,
                       timeout=timeout, stdin=subprocess.DEVNULL)
    err = r.stderr.decode('utf-8', 'replace')
    m = COUNT_LINE.search(err)
    if r.returncode != 0 or not m:
        return None, r.stdout.decode('utf-8', 'replace')
    return {k: int(v) for k, v in (p.split('=') for p in m.group(1).split())}, r.stdout.decode('utf-8', 'replace')


def perf_status():
    """→ (usable, reason). Tried for real rather than inferred from the sysctl:
    a container can refuse the syscall whatever the value says."""
    if not shutil.which('perf'):
        return False, 'no `perf` on PATH'
    try:
        level = open('/proc/sys/kernel/perf_event_paranoid').read().strip()
    except OSError:
        level = '?'
    with tempfile.NamedTemporaryFile('r', suffix='.perf') as out:
        r = subprocess.run(['perf', 'stat', '-x,', '-e', 'instructions:u', '-o', out.name, '--', 'true'],
                           capture_output=True, stdin=subprocess.DEVNULL)
        if r.returncode == 0 and _parse_perf(open(out.name).read()) is not None:
            return True, 'perf_event_paranoid=%s' % level
    return False, ('perf_event_paranoid=%s — `sudo sysctl kernel.perf_event_paranoid=1` enables it; '
                   'put it back to %s afterwards' % (level, level))


def _parse_perf(text):
    for line in text.splitlines():
        f = line.split(',')
        if len(f) > 2 and f[2].startswith('instructions'):
            return int(f[0]) if f[0].isdigit() else None
    return None


def instructions(cmd, cwd=None, runs=7, timeout=300):
    """→ (median, spread, stdout, exit status). `spread` is (max − min) / median:
    0.00 on the VM, which is deterministic; the tree-walker and Python move by
    about half a percent, since their hash seeds are per process."""
    # The program's own exit status comes from a run WITHOUT perf: `perf stat`
    # passes on an ordinary exit code but answers 0 for a child killed by a
    # signal — a tree-walker that aborted on its stack (134) was being counted
    # as a measurement (found 2026-10-14, `recursion_depth`).
    r = subprocess.run(cmd, cwd=cwd, capture_output=True, timeout=timeout, stdin=subprocess.DEVNULL)
    if r.returncode != 0:
        code = r.returncode if r.returncode > 0 else 128 - r.returncode
        return None, None, r.stdout.decode('utf-8', 'replace'), code
    vals, out, code = [], '', 0
    with tempfile.NamedTemporaryFile('r', suffix='.perf') as po:
        for _ in range(runs):
            r = subprocess.run(['perf', 'stat', '-x,', '-e', 'instructions:u', '-o', po.name, '--'] + cmd,
                               cwd=cwd, capture_output=True, timeout=timeout, stdin=subprocess.DEVNULL)
            out, code = r.stdout.decode('utf-8', 'replace'), r.returncode
            n = _parse_perf(open(po.name).read())
            if code != 0 or n is None:
                return None, None, out, code or 1
            vals.append(n)
    med = statistics.median(vals)
    return med, ((max(vals) - min(vals)) / med if med else 0.0), out, 0


def cpu_ms(cmd, cwd=None, runs=5, timeout=300):
    """→ (median CPU ms, spread, stdout, exit status) — user + system time of the
    child, from `os.wait4`, so one measurement never inherits another's."""
    vals, out = [], ''
    for _ in range(runs):
        with tempfile.TemporaryFile() as so:
            p = subprocess.Popen(cmd, cwd=cwd, stdout=so, stderr=subprocess.DEVNULL, stdin=subprocess.DEVNULL)
            try:
                _, status, ru = os.wait4(p.pid, 0)
            except BaseException:
                p.kill()
                raise
            p.returncode = os.waitstatus_to_exitcode(status)
            so.seek(0)
            out = so.read().decode('utf-8', 'replace')
        if p.returncode != 0:
            return None, None, out, p.returncode
        vals.append((ru.ru_utime + ru.ru_stime) * 1000)
    med = statistics.median(vals)
    return med, ((max(vals) - min(vals)) / med if med else 0.0), out, 0


class Meter:
    """The time instrument a run uses: instructions when perf allows it, else
    the clock. One per run, chosen once, so a table never mixes the two."""

    def __init__(self, force_clock=False, runs=None):
        ok, self.reason = (False, 'asked for with --clock') if force_clock else perf_status()
        self.unit = 'instructions' if ok else 'cpu-ms'
        self.runs = runs or (7 if ok else 5)

    def __call__(self, cmd, cwd=None, timeout=300):
        fn = instructions if self.unit == 'instructions' else cpu_ms
        return fn(cmd, cwd, self.runs, timeout)

    def fmt(self, v):
        if v is None:
            return '—'
        if v <= 0:          # start-up subtracted from a program that is little else
            return '~0'
        return '%.1fM' % (v / 1e6) if self.unit == 'instructions' else '%.0f' % v

    def header(self):
        if self.unit == 'instructions':
            return 'time unit: instructions:u (perf, median of %d; %s)' % (self.runs, self.reason)
        return ('time unit: CPU ms, median of %d — perf unavailable (%s). '
                'Clock figures move ±20%% between runs: compare only within one run.' % (self.runs, self.reason))
