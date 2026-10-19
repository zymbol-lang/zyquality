#!/usr/bin/env python3
"""Generate the interactive web/benchmarks.html and its Markdown twin from a
langs.py run (every language and every Zymbol engine). No figure is typed by
hand: re-measure, then

    python3 langs_page.py --data out.json --commit <sha> --date <yyyy-mm-dd>


The page carries its data as JSON and draws itself: the reader picks the
reference (any language or Zymbol engine = 1.00), the measure (whole process
or start-up subtracted) and the display (relative or milliseconds), and the
cards, the bars and the table follow. Without JavaScript it shows a static
table against Zymbol v0.0.11, which is also what the Markdown twin carries."""
import argparse, json, math, os, re, html

_ap = argparse.ArgumentParser(description='Write web/benchmarks.html and benchmarks.md from a langs.py run.')
_ap.add_argument('--data', default=os.path.join(os.path.dirname(os.path.abspath(__file__)), 'langs_2026-10-18.json'),
                 help='the JSON langs.py wrote, with ZYMBOL_OLD set so all four Zymbol engines are in it')
_ap.add_argument('--web', default=os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', '..', '..', 'web'),
                 help='the web repository (its install.html gives the header and footer)')
_ap.add_argument('--commit', default='7ef269c', help='the interpreter commit that was measured')
_ap.add_argument('--date', default='2026-10-18')
_a = _ap.parse_args()
WEB = os.path.abspath(_a.web)
L = json.load(open(_a.data))
COMMIT = _a.commit
DATE = _a.date
REPO = 'https://github.com/zymbol-lang/zyquality/tree/v0.0.11/bench/big'
NET_MIN = 100

def gm(xs):
    return math.exp(sum(math.log(x) for x in xs) / len(xs))

def _ver(s):
    m = re.search(r'v?\d+\.\d+\.\d+', s or '')
    return m.group(0) if m else (s or '?')

# ── the languages, in the order the page shows them ─────────────────────────
INFO = {
    'zymbol':        ('Zymbol v0.0.11 · VM', 'Zymbol', 'zymbol', 'v0.0.11', 'register VM, the default'),
    'zymbol_tw':     ('Zymbol v0.0.11 · tree-walker', 'Zymbol TW', 'zymbol', 'v0.0.11', 'tree-walker, --tw'),
    'zymbol_old':    ('Zymbol v0.0.10 · VM', 'Zymbol 0.10 VM', 'zymbol', 'v0.0.10', 'register VM, --vm'),
    'zymbol_old_tw': ('Zymbol v0.0.10 · tree-walker', 'Zymbol 0.10 TW', 'zymbol', 'v0.0.10', 'tree-walker, its default'),
    'php':    ('PHP', 'PHP', 'interp', None, 'Zend VM; opcache JIT off on the command line'),
    'lua':    ('Lua', 'Lua', 'interp', None, 'PUC Lua, register VM'),
    'perl':   ('Perl', 'Perl', 'interp', None, 'interpreter'),
    'ruby':   ('Ruby', 'Ruby', 'interp', None, 'CRuby VM; YJIT off without --yjit'),
    'python': ('Python', 'Python', 'interp', None, 'CPython'),
    'node':   ('JavaScript · Node', 'JavaScript', 'jit', None, 'V8, JIT compiler'),
    'julia':  ('Julia', 'Julia', 'jit', None, 'JIT compiler (LLVM)'),
}
keys = [l['key'] for l in L['langs']]
rows = L['rows']
progs = [r['program'] for r in rows]
ms = {r['program']: {k: r['langs'][k]['wall_ms'] for k in keys} for r in rows}
cpu = {r['program']: {k: r['langs'][k]['ms'] for k in keys} for r in rows}
start = {k: L['startup'][k]['wall_ms'] for k in keys}
agree = sum(1 for r in rows for k in keys if r['langs'][k]['ok'])
total = sum(len(r['langs']) for r in rows)

rel_zy = {k: gm([ms[p][k] / ms[p]['zymbol'] for p in progs]) for k in keys}
interp_others = sorted([k for k in keys if INFO[k][2] == 'interp'], key=lambda k: rel_zy[k])
jit = sorted([k for k in keys if INFO[k][2] == 'jit'], key=lambda k: rel_zy[k])
zy = ['zymbol', 'zymbol_tw', 'zymbol_old', 'zymbol_old_tw']
ORDER = [k for k in zy if k in keys] + interp_others + jit

def version(k):
    if INFO[k][3]:
        return INFO[k][3]
    return _ver(L['versions'].get(k, ''))

net_progs = [p for p in progs if ms[p]['zymbol'] >= NET_MIN]
def _net(p, k):
    return max(ms[p][k] - start[k], 1.0)
net_zy = {k: gm([_net(p, k) / ms[p]['zymbol'] for p in net_progs]) for k in keys}
cpu_over_wall = {k: gm([cpu[p][k] / ms[p][k] for p in progs]) for k in keys}

DESC = {
    'array_update': 'write 3 000 slots of a 20 000-slot array',
    'collatz': 'longest Collatz chain below 60 000',
    'fib_rec': 'naive recursive fib(34) — 18 million calls',
    'hof_chain': 'map, filter, reduce over 100 000 numbers, 25 times',
    'loop_mod': 'ten million turns of integer arithmetic',
    'mandelbrot': '250×250 Mandelbrot set, floating point',
    'match_loop': 'classify three million numbers by range',
    'matmul': '150×150 integer matrix product',
    'nqueens': 'every solution of 10 queens',
    'primes_trial': 'primes below 300 000 by trial division',
    'sort_builtin': 'sort 600 000 numbers, natural order',
    'sort_cmp_300k': 'sort 300 000 numbers with a comparator',
    'sort_cmp_4k': 'sort 4 000 numbers with a comparator',
    'strings_scan_long': 'count vowels in an 88 000-character text',
    'strings_scan_short': 'count vowels in a short text, 200 times',
    'tak': 'Takeuchi function, deep recursion',
}

def f_ms(x):
    return '%d' % round(x) if x >= 10 else '%.1f' % x

def f_x(x):
    return '%.2f×' % x

def en_list(ws):
    return ', '.join(ws[:-1]) + ' and ' + ws[-1] if len(ws) > 1 else ws[0]

# facts for the static text, all against Zymbol v0.0.11
INTERP_ALL = ['zymbol'] + interp_others
interp_rank = sorted(INTERP_ALL, key=lambda k: rel_zy[k])
zy_rank = interp_rank.index('zymbol') + 1
ORD = {1: 'the fastest', 2: 'the second fastest', 3: 'the third fastest', 4: 'the fourth fastest',
       5: 'the fifth fastest', 6: 'the sixth fastest'}
WORDS = {5: 'five', 6: 'six', 7: 'seven', 8: 'eight', 9: 'nine'}
n_interp = len(INTERP_ALL)
n_lang = 1 + len(interp_others) + len(jit)
beats = {k: [p for p in progs if ms[p][k] < ms[p]['zymbol']] for k in interp_others}
ahead = [k for k in interp_others if rel_zy[k] < 1]
behind = [k for k in interp_others if rel_zy[k] > 1]
net_ahead = sorted([k for k in interp_others if net_zy[k] < net_zy['zymbol']], key=lambda k: net_zy[k])
speed_tw10 = gm([ms[p]['zymbol_old_tw'] / ms[p]['zymbol'] for p in progs]) if 'zymbol_old_tw' in keys else None
speed_vm10 = gm([ms[p]['zymbol_old'] / ms[p]['zymbol'] for p in progs]) if 'zymbol_old' in keys else None
short = {k: INFO[k][1] for k in keys}

DATA = {
    'date': DATE, 'commit': COMMIT, 'runs': L['runs'], 'netMin': NET_MIN,
    'langs': [{'key': k, 'label': INFO[k][0], 'short': INFO[k][1], 'group': INFO[k][2],
               'version': version(k), 'note': INFO[k][4], 'startup': round(start[k], 2)} for k in ORDER],
    'programs': [{'name': p, 'desc': DESC[p], 'ms': {k: round(ms[p][k], 2) for k in ORDER}} for p in progs],
}

# ── HTML ─────────────────────────────────────────────────────────────────────
src = open(WEB + '/install.html').read()
top = src[:src.index('<!-- ═══ HERO ═══ -->')]
top = top.replace('<title>Install — Zymbol-Lang</title>', '<title>Benchmarks — Zymbol-Lang</title>')
top = re.sub(r'<meta name="description" content="[^"]*">',
             '<meta name="description" content="How fast is Zymbol? Sixteen programs in %s languages and four Zymbol engines, the same printed answer, measured on one machine. Pick any of them as the reference.">' % WORDS[n_lang], top)
top = top.replace('href="install.md"', 'href="benchmarks.md"')
CSS = '''
  <style>
    .bm-ctl { display:flex; flex-wrap:wrap; gap:1rem 2rem; margin:1.25rem 0 0.5rem; align-items:flex-start; }
    .bm-ctl .grp { display:flex; flex-direction:column; gap:0.4rem; }
    .bm-ctl .lbl { font-family:var(--mono); font-size:0.66rem; color:var(--mid); text-transform:uppercase; letter-spacing:0.08em; }
    .bm-seg { display:inline-flex; border:1px solid var(--line); border-radius:var(--radius); overflow:hidden; }
    .bm-seg button { background:var(--bg2); color:var(--text); border:0; border-right:1px solid var(--line); padding:0.4rem 0.8rem; font:inherit; font-size:0.8rem; cursor:pointer; }
    .bm-seg button:last-child { border-right:0; }
    .bm-seg button[aria-pressed="true"] { background:var(--green-dim); color:var(--green); font-weight:600; }
    .bm-refs { display:flex; flex-wrap:wrap; gap:0.35rem 0.4rem; align-items:center; max-width:100%; }
    .bm-refs .sep { width:1px; height:1.4rem; background:var(--line); margin:0 0.25rem; }
    .bm-chip { background:var(--bg2); color:var(--text); border:1px solid var(--line); border-radius:999px; padding:0.25rem 0.7rem; font:inherit; font-size:0.78rem; cursor:pointer; }
    .bm-chip:hover { border-color:var(--mid); color:var(--hi); }
    .bm-chip[aria-pressed="true"] { background:var(--green); border-color:var(--green); color:var(--bg); font-weight:600; }
    .bm-chip.jit { border-color:color-mix(in srgb, var(--op) 45%, var(--line)); }
    .bm-chip.jit[aria-pressed="true"] { background:var(--op); border-color:var(--op); }
    .bm-chip.zy { border-style:dashed; }
    .bm-check { font-size:0.8rem; color:var(--text); display:flex; align-items:center; gap:0.45rem; cursor:pointer; }
    .bm-jit { font-family:var(--mono); font-size:0.62rem; font-weight:600; letter-spacing:0.08em; color:var(--op);
              border:1px solid color-mix(in srgb, var(--op) 55%, transparent); border-radius:999px; padding:0.05rem 0.45rem; }
    .bm-grid { display:grid; grid-template-columns:repeat(4,minmax(0,1fr)); gap:1.1rem 0.75rem; margin:1.4rem 0 0.5rem; }
    .bm-card { background:var(--bg2); border:1px solid var(--line); border-radius:var(--radius-lg); padding:0.9rem 1rem; position:relative; cursor:pointer; text-align:left; font:inherit; color:inherit; }
    .bm-card:hover { border-color:var(--mid); }
    .bm-card.ref { border-color:var(--green); background:var(--green-dim); }
    .bm-card.jit { border-color:color-mix(in srgb, var(--op) 45%, var(--line)); }
    .bm-card.jit.ref { border-color:var(--op); background:color-mix(in srgb, var(--op) 12%, transparent); }
    .bm-card .k { font-family:var(--mono); font-size:0.68rem; color:var(--mid); text-transform:uppercase; letter-spacing:0.06em; }
    .bm-card .v { font-family:var(--mono); font-size:1.55rem; font-weight:600; color:var(--white); margin:0.15rem 0; }
    .bm-card.ref .v { color:var(--green); }
    .bm-card.jit.ref .v { color:var(--op); }
    .bm-card .s { font-size:0.76rem; color:var(--text); }
    .bm-card .s2 { font-family:var(--mono); font-size:0.68rem; color:var(--mid); margin-top:0.4rem; padding-top:0.35rem; border-top:1px dashed var(--line); }
    .bm-card .bm-jit { position:absolute; top:-0.62rem; left:0.85rem; background:var(--bg); }
    .bm-bars { margin:1.1rem 0 0.25rem; display:flex; flex-direction:column; gap:0.42rem; }
    .bm-bar { display:grid; grid-template-columns:14rem 1fr 5.2rem; align-items:center; gap:0.6rem; font-size:0.8rem; }
    .bm-bar .n { color:var(--hi); white-space:nowrap; overflow:hidden; text-overflow:ellipsis; }
    .bm-bar .n small { color:var(--mid); }
    .bm-bar .t { display:block; height:0.9rem; background:var(--bg3); border-radius:3px; overflow:hidden; position:relative; }
    .bm-bar .f { display:block; height:100%; background:var(--dim); border-radius:3px; }
    .bm-bar.zy .f { background:color-mix(in srgb, var(--green) 55%, var(--dim)); }
    .bm-bar.ref .f { background:var(--green); }
    .bm-bar.jit .f { background:var(--op); opacity:0.75; }
    .bm-bar.jit.ref .f { opacity:1; }
    .bm-bar .one { position:absolute; top:-2px; bottom:-2px; width:1px; background:var(--green); }
    .bm-bar .x { font-family:var(--mono); color:var(--hi); text-align:right; }
    .bm-sep { display:flex; align-items:center; gap:0.6rem; margin:0.5rem 0 0.05rem; }
    .bm-sep::after { content:''; flex:1; border-top:1px dashed color-mix(in srgb, var(--op) 45%, var(--line)); }
    .bm-sep.zy::after { border-top-color:var(--line); }
    .bm-sep .t2 { font-family:var(--mono); font-size:0.62rem; color:var(--mid); letter-spacing:0.08em; text-transform:uppercase; }
    .bm-table td.num, .bm-table th.num { text-align:right; font-family:var(--mono); white-space:nowrap; }
    .bm-table td.best { color:var(--green); font-weight:600; }
    .bm-table td.refcol, .bm-table th.refcol { background:var(--green-dim); }
    .bm-table td .d { display:block; font-size:0.7rem; color:var(--mid); font-family:var(--ui); }
    .bm-table th.jit, .bm-table td.jit { color:var(--op); }
    .bm-table .first { border-left:1px dashed color-mix(in srgb, var(--op) 45%, var(--line)); }
    .bm-table .zyfirst { border-left:1px dashed var(--line); }
    .bm-table tr.grp th { border-bottom:none; padding-bottom:0; font-size:0.6rem; }
    .bm-table th.lang { cursor:pointer; }
    .bm-table th.lang:hover { color:var(--hi); }
    .bm-note { font-size:0.82rem; color:var(--text); border-left:2px solid var(--green-mid); padding:0.4rem 0 0.4rem 0.9rem; margin:1rem 0; }
    .bm-list { margin:0.5rem 0 0 1.1rem; font-size:0.86rem; color:var(--text); line-height:1.7; }
    .bm-list code, .bm-note code, .bm-sub code { font-family:var(--mono); font-size:0.8rem; color:var(--hi); }
    .bm-sub { font-size:0.85rem; color:var(--text); margin-top:0.35rem; }
    @media (max-width: 900px) { .bm-grid { grid-template-columns:repeat(2,minmax(0,1fr)); } }
    @media (max-width: 640px) {
      .bm-bar { grid-template-columns:8.5rem 1fr 4.2rem; font-size:0.72rem; }
      .bm-card .v { font-size:1.3rem; }
      .bm-ctl { gap:0.9rem; }
    }
  </style>'''
top = top.replace('<link rel="stylesheet" href="src/css/site.css">', '<link rel="stylesheet" href="src/css/site.css">' + CSS)

foot = src[src.index('<!-- ═══ FOOTER ═══ -->'):]
foot = foot.replace('<a href="install.html">Download</a>', '<a href="install.html">Download</a>\n      <a href="benchmarks.html">Benchmarks</a>')
foot = re.sub(r'\n  // Copy hash buttons.*?\n  \}\);\n', '\n', foot, flags=re.S)

# static fallback table (no JavaScript): Zymbol v0.0.11 = 1.00
def static_table():
    cols = ['zymbol'] + interp_others + jit
    head = '<tr><th>Program</th>' + ''.join('<th class="num">%s</th>' % html.escape(short[k]) for k in cols) + '</tr>'
    body = []
    for p in progs:
        body.append('<tr><td><code>%s</code></td>' % p + ''.join('<td class="num">%s</td>' % f_ms(ms[p][k]) for k in cols) + '</tr>')
    body.append('<tr><td><strong>geometric mean, Zymbol v0.0.11 = 1</strong></td>' + ''.join('<td class="num">%s</td>' % f_x(rel_zy[k]) for k in cols) + '</tr>')
    return '<div class="dl-table-wrap"><table class="dl-table bm-table"><thead>%s</thead><tbody>%s</tbody></table></div>' % (head, ''.join(body))

# The Zymbol versions against each other — Zymbol only, no other language.
EVO = [k for k in ('zymbol', 'zymbol_old', 'zymbol_old_tw') if k in keys]
EVO_HEAD = {'zymbol': 'v0.0.11 · VM', 'zymbol_old': 'v0.0.10 · <code>--vm</code>', 'zymbol_old_tw': 'v0.0.10 · tree-walker<br>(its default)'}
def evo_table():
    head = '<tr><th>Program</th>' + ''.join('<th class="num%s">%s</th>' % (' refcol' if k == 'zymbol' else '', EVO_HEAD[k]) for k in EVO) + '</tr>'
    body = []
    for p in progs:
        cells = []
        for k in EVO:
            r = ms[p][k] / ms[p]['zymbol']
            cells.append('<td class="num%s">%s ms<span class="d">%s</span></td>' % (' refcol best' if k == 'zymbol' else '', f_ms(ms[p][k]), f_x(r)))
        body.append('<tr><td><code>%s</code></td>%s</tr>' % (p, ''.join(cells)))
    body.append('<tr><td><strong>geometric mean, v0.0.11 = 1</strong></td>' + ''.join(
        '<td class="num%s">%s</td>' % (' refcol best' if k == 'zymbol' else '', f_x(gm([ms[p][k] / ms[p]['zymbol'] for p in progs]))) for k in EVO) + '</tr>')
    return '<div class="dl-table-wrap" style="margin-top:1rem"><table class="dl-table bm-table"><thead>%s</thead><tbody>%s</tbody></table></div>' % (head, ''.join(body))

ver_rows = '\n            '.join(
    '<tr><td>%s</td><td>%s</td><td>%s</td></tr>' % (
        html.escape(INFO[k][0]),
        html.escape('v0.0.11 (development branch, %s)' % COMMIT if k in ('zymbol', 'zymbol_tw') else version(k)),
        ('<span class="bm-jit">JIT</span> compiler' if INFO[k][2] == 'jit' else html.escape(INFO[k][4]).replace('`', '')))
    for k in ORDER)

JS = r'''
<script type="application/json" id="bm-data">%(data)s</script>
<script>
(function () {
  var D = JSON.parse(document.getElementById('bm-data').textContent);
  var langs = D.langs, byKey = {};
  langs.forEach(function (l) { byKey[l.key] = l; });
  var progs = D.programs;
  var netProgs = progs.filter(function (p) { return p.ms.zymbol >= D.netMin; });
  var q = new URLSearchParams(location.search);
  var st = {
    ref: byKey[q.get('ref')] ? q.get('ref') : 'zymbol',
    measure: q.get('measure') === 'net' ? 'net' : 'whole',
    show: q.get('show') === 'ms' ? 'ms' : 'rel',
    engines: q.get('engines') === 'all' || /^zymbol_/.test(q.get('ref') || '')
  };
  function gm(xs) { var s = 0; xs.forEach(function (x) { s += Math.log(x); }); return Math.exp(s / xs.length); }
  function net(p, k) { return Math.max(p.ms[k] - byKey[k].startup, 1); }
  function fms(x) { return x >= 10 ? Math.round(x).toString() : x.toFixed(1); }
  function fx(x) { return x.toFixed(2) + '×'; }
  function esc(s) { return String(s).replace(/[&<>"]/g, function (c) { return {'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;'}[c]; }); }
  function visible() {
    return langs.filter(function (l) { return l.group !== 'zymbol' || l.key === 'zymbol' || st.engines || l.key === st.ref; });
  }
  // The value of a language under the current state: relative to the
  // reference's WHOLE process (one reference for both measures), or ms.
  function value(k) {
    var ps = st.measure === 'net' ? netProgs : progs;
    if (st.show === 'ms') return gm(ps.map(function (p) { return st.measure === 'net' ? net(p, k) : p.ms[k]; }));
    return gm(ps.map(function (p) { return (st.measure === 'net' ? net(p, k) : p.ms[k]) / p.ms[st.ref]; }));
  }
  function against(x, refName) {
    if (Math.abs(x - 1) < 0.005) return 'the reference';
    if (Math.abs(x - 1) < 0.03) return 'about the same as ' + refName;
    return x > 1 ? (x.toFixed(1) + '× slower than ' + refName) : ((1 / x).toFixed(1) + '× faster than ' + refName);
  }
  function setState(k, v) {
    st[k] = v;
    var u = new URLSearchParams();
    if (st.ref !== 'zymbol') u.set('ref', st.ref);
    if (st.measure !== 'whole') u.set('measure', st.measure);
    if (st.show !== 'rel') u.set('show', st.show);
    if (st.engines) u.set('engines', 'all');
    history.replaceState(null, '', location.pathname + (u.toString() ? '?' + u : '') + location.hash);
    render();
  }
  function seg(id, key, opts) {
    var el = document.getElementById(id);
    el.innerHTML = opts.map(function (o) {
      return '<button type="button" data-v="' + o[0] + '" aria-pressed="' + (st[key] === o[0]) + '">' + o[1] + '</button>';
    }).join('');
    el.querySelectorAll('button').forEach(function (b) { b.onclick = function () { setState(key, b.dataset.v); }; });
  }
  function render() {
    var ref = byKey[st.ref], vis = visible();
    seg('bm-measure', 'measure', [['whole', 'Whole process'], ['net', 'Start-up subtracted']]);
    seg('bm-show', 'show', [['rel', 'Relative ×'], ['ms', 'Milliseconds']]);
    var eng = document.getElementById('bm-engines'); eng.checked = st.engines;
    // reference chips
    var groups = [['zymbol'], ['interp'], ['jit']], html = [];
    groups.forEach(function (g, i) {
      if (i) html.push('<span class="sep"></span>');
      if (g[0] === 'jit') html.push('<span class="bm-jit">JIT</span>');
      vis.filter(function (l) { return l.group === g[0]; }).forEach(function (l) {
        html.push('<button type="button" class="bm-chip ' + (l.group === 'jit' ? 'jit' : (l.group === 'zymbol' ? 'zy' : '')) +
          '" data-k="' + l.key + '" aria-pressed="' + (l.key === st.ref) + '">' + esc(l.short) + '</button>');
      });
    });
    var refs = document.getElementById('bm-refs'); refs.innerHTML = html.join('');
    refs.querySelectorAll('button').forEach(function (b) { b.onclick = function () { setState('ref', b.dataset.k); }; });
    // headline
    var unit = st.show === 'ms' ? 'geometric mean of milliseconds' : (esc(ref.label) + ' = 1.00');
    document.getElementById('bm-what').innerHTML = (st.measure === 'net'
      ? 'Start-up subtracted — each language its own, the reference included — over the ' + netProgs.length + ' programs Zymbol v0.0.11 takes ' + D.netMin + ' ms or more on. '
      : 'Whole process, start-up included, over all ' + progs.length + ' programs. ') +
      (st.show === 'ms' ? 'Shown as the geometric mean of elapsed milliseconds.' :
        'Shown against <strong>' + esc(ref.label) + '</strong>' + (st.measure === 'net' ? '\'s whole process = 1.00 — so the reference itself drops by its own ' + fms(ref.startup) + ' ms of start-up' : ' = 1.00') + '; above 1 slower, below 1 faster.');
    // cards
    var vals = {}; vis.forEach(function (l) { vals[l.key] = value(l.key); });
    var refName = ref.short;
    document.getElementById('bm-cards').innerHTML = vis.map(function (l) {
      var v = vals[l.key];
      var rel = st.show === 'ms' ? v / vals[st.ref] : v;
      var sub = l.key === st.ref ? (st.measure === 'net' ? 'the reference, its own start-up taken off' : 'the reference') : against(st.show === 'ms' ? rel : v, refName);
      return '<button type="button" class="bm-card ' + (l.group === 'jit' ? 'jit ' : '') + (l.key === st.ref ? 'ref' : '') + '" data-k="' + l.key + '" title="Make ' + esc(l.label) + ' the reference">' +
        (l.group === 'jit' ? '<span class="bm-jit">JIT</span>' : '') +
        '<div class="k">' + esc(l.label) + ' ' + esc(l.group === 'zymbol' ? '' : l.version) + '</div>' +
        '<div class="v">' + (st.show === 'ms' ? fms(v) + ' ms' : fx(v)) + '</div>' +
        '<div class="s">' + esc(sub) + '</div>' +
        '<div class="s2">' + esc(l.note) + ' · start-up ' + fms(l.startup) + ' ms</div></button>';
    }).join('');
    document.querySelectorAll('#bm-cards .bm-card').forEach(function (c) { c.onclick = function () { setState('ref', c.dataset.k); }; });
    // bars
    var top = Math.max.apply(null, vis.map(function (l) { return vals[l.key]; }));
    var refMark = st.show === 'ms' ? vals[st.ref] : 1;
    var bars = [], prev = null;
    vis.forEach(function (l) {
      if (prev && prev !== l.group) {
        bars.push(l.group === 'jit' ? '<div class="bm-sep"><span class="bm-jit">JIT</span></div>' : '<div class="bm-sep zy"><span class="t2">other interpreters</span></div>');
      }
      prev = l.group;
      var v = vals[l.key];
      bars.push('<div class="bm-bar ' + (l.group === 'jit' ? 'jit ' : '') + (l.group === 'zymbol' ? 'zy ' : '') + (l.key === st.ref ? 'ref' : '') + '">' +
        '<span class="n">' + esc(l.label) + (st.measure === 'net' ? ' <small>−' + fms(l.startup) + ' ms</small>' : '') + '</span>' +
        '<span class="t"><span class="f" style="width:' + (100 * v / top).toFixed(1) + '%%"></span>' +
        '<span class="one" style="left:' + (100 * refMark / top).toFixed(1) + '%%"></span></span>' +
        '<span class="x">' + (st.show === 'ms' ? fms(v) + ' ms' : fx(v)) + '</span></div>');
    });
    document.getElementById('bm-bars').innerHTML = bars.join('');
    // table
    var ps = st.measure === 'net' ? netProgs : progs;
    var interp = vis.filter(function (l) { return l.group !== 'jit'; });
    var jits = vis.filter(function (l) { return l.group === 'jit'; });
    var cols = interp.concat(jits);
    function cell(p, l) { var x = st.measure === 'net' ? net(p, l.key) : p.ms[l.key]; return st.show === 'ms' ? fms(x) : fx(x / p.ms[st.ref]); }
    function cls(l, i) {
      var c = ['num'];
      if (l.key === st.ref) c.push('refcol');
      if (l.group === 'jit') { c.push('jit'); if (l === jits[0]) c.push('first'); }
      if (l.group !== 'zymbol' && i > 0 && cols[i - 1].group === 'zymbol') c.push('zyfirst');
      return c.join(' ');
    }
    var thead = '<tr class="grp"><th></th><th colspan="' + interp.length + '" class="num">interpreters' + (interp.some(function (l) { return l.group === 'zymbol'; }) && st.engines ? ' · Zymbol engines first' : '') + '</th>' +
      (jits.length ? '<th colspan="' + jits.length + '" class="jit first num"><span class="bm-jit">JIT</span></th>' : '') + '</tr>' +
      '<tr><th>Program</th>' + cols.map(function (l, i) { return '<th class="lang ' + cls(l, i) + '" data-k="' + l.key + '" title="Make ' + esc(l.label) + ' the reference">' + esc(l.short) + '</th>'; }).join('') + '</tr>';
    var body = ps.map(function (p) {
      var best = null;
      interp.forEach(function (l) { if (l.group !== 'zymbol' || l.key === 'zymbol') { var x = p.ms[l.key]; if (best === null || x < p.ms[best]) best = l.key; } });
      return '<tr><td><code>' + esc(p.name) + '</code><span class="d">' + esc(p.desc) + '</span></td>' +
        cols.map(function (l, i) { return '<td class="' + cls(l, i) + (l.key === best ? ' best' : '') + '">' + cell(p, l) + '</td>'; }).join('') + '</tr>';
    });
    body.push('<tr><td><strong>geometric mean' + (st.show === 'ms' ? ', ms' : ', ' + esc(ref.short) + ' = 1') + '</strong></td>' +
      cols.map(function (l, i) { return '<td class="' + cls(l, i) + '">' + (st.show === 'ms' ? fms(vals[l.key]) : fx(vals[l.key])) + '</td>'; }).join('') + '</tr>');
    document.getElementById('bm-table').innerHTML = '<thead>' + thead + '</thead><tbody>' + body.join('') + '</tbody>';
    document.querySelectorAll('#bm-table th.lang').forEach(function (h) { h.onclick = function () { setState('ref', h.dataset.k); }; });
    document.getElementById('bm-tablewhat').textContent = (st.show === 'ms' ? 'Milliseconds of elapsed time' : 'Elapsed time against ' + ref.label + ' (its time on that program = 1)') +
      (st.measure === 'net' ? ', start-up subtracted, ' + netProgs.length + ' programs' : ', start-up included') +
      ', median of ' + D.runs + ' runs. Green: the fastest interpreter on that program. Click a column to make it the reference.';
  }
  document.getElementById('bm-engines').onchange = function (e) {
    if (!e.target.checked && /^zymbol_/.test(st.ref)) st.ref = 'zymbol';
    setState('engines', e.target.checked);
  };
  document.getElementById('bm-live').hidden = false;
  render();
}());
</script>
'''

body = '''<!-- ═══ HERO ═══ -->
<div class="install-hero">
  <div class="section-tag">performance · measured %(date)s</div>
  <h1>How fast is Zymbol?</h1>
  <p>Sixteen programs, %(nword)s languages and four Zymbol engines, the same printed answer. Pick any of them as the reference and the rest is measured against it. One machine, elapsed time per process — and the programs, their twins and the script that measured them are public.</p>
  <div class="hero-actions">
    <a href="#compare" class="btn-primary">Compare</a>
    <a href="#evolution" class="btn-ghost">v0.0.10 → v0.0.11</a>
    <a href="#method" class="btn-ghost">How it was measured</a>
    <a href="%(repo)s" target="_blank" rel="noopener" class="btn-ghost">The programs ↗</a>
  </div>
</div>

<!-- ═══ COMPARE ═══ -->
<div class="install-section" id="compare">
  <div class="container">
    <h2>Compare</h2>
    <p class="section-sub">Choose the reference — it becomes 1.00 — and how to look at the figures. The link in the address bar keeps your choice.</p>
    <div id="bm-live" hidden>
      <div class="bm-ctl">
        <div class="grp" style="flex:1 1 100%%"><span class="lbl">Reference = 1.00</span><div class="bm-refs" id="bm-refs"></div></div>
        <div class="grp"><span class="lbl">Measure</span><div class="bm-seg" id="bm-measure"></div></div>
        <div class="grp"><span class="lbl">Show</span><div class="bm-seg" id="bm-show"></div></div>
        <div class="grp"><span class="lbl">Zymbol</span><label class="bm-check"><input type="checkbox" id="bm-engines"> all four engines (v0.0.10 and the tree-walkers)</label></div>
      </div>
      <p class="bm-sub" id="bm-what"></p>
      <div class="bm-grid" id="bm-cards"></div>
      <div class="bm-bars" id="bm-bars"></div>
      <h3 style="margin-top:2rem;font-size:1.05rem">Program by program</h3>
      <p class="bm-sub" id="bm-tablewhat"></p>
      <div class="dl-table-wrap" style="margin-top:0.75rem"><table class="dl-table bm-table" id="bm-table"></table></div>
    </div>
    <noscript>
      <p class="bm-sub">Elapsed milliseconds, start-up included, median of %(runs)d runs; the last row against Zymbol v0.0.11 = 1. With JavaScript this section lets you pick the reference.</p>
      %(static)s
    </noscript>
    <p class="bm-note">%(interp_en)s are interpreters: they run the program without turning it into machine code. PHP's opcache JIT is off on the command line and Ruby's YJIT is off without <code>--yjit</code>, so both run here as interpreters. JavaScript (Node, V8) and Julia, marked <span class="bm-jit">JIT</span>, compile to machine code while they run, and are here as the reference of what compiling buys. Julia starts in %(jl_start)s ms before running anything: on programs this short, start-up is a large part of its figures — subtract it and Julia comes to %(jl_net)s of Zymbol, next to JavaScript's %(js_net)s.</p>
    <p class="bm-note">Said plainly, with Zymbol v0.0.11 as the reference: Zymbol is %(rank)s. %(lead)s — mature virtual machines with decades of tuning behind them, and Lua's is a register machine like Zymbol's; they are the bar now. Zymbol is ahead of %(behind)s in the mean%(rest)s. With start-up subtracted, %(net_ahead)s ahead of it. The deep-recursion programs, <code>fib_rec</code> and <code>tak</code>, are where a call still costs Zymbol most, and that is the next thing being worked on.</p>
  </div>
</div>

<!-- ═══ EVOLUTION ═══ -->
<div class="install-section" id="evolution">
  <div class="container">
    <h2>From v0.0.10 to v0.0.11</h2>
    <p class="section-sub">Zymbol against itself — no other language here. v0.0.10 ran the tree-walker by default; its register VM was <code>zymbol run --vm</code>. From v0.0.11 the VM is the default, and this release's work went into it. Elapsed milliseconds, median of %(runs)d runs, and each against v0.0.11 = 1.00.</p>
    <div class="bm-grid" style="grid-template-columns:repeat(2,minmax(0,1fr))">
      <div class="bm-card ref" style="cursor:default"><div class="k">what a user sees</div><div class="v">%(sp_tw).1f× faster</div><div class="s">v0.0.11 against v0.0.10 as it ran by default (tree-walker), elapsed time</div></div>
      <div class="bm-card" style="cursor:default"><div class="k">VM against VM</div><div class="v">%(sp_vm).1f× faster</div><div class="s">v0.0.11 against v0.0.10's <code>--vm</code>, elapsed time</div></div>
    </div>
    %(evo)s
    <p class="bm-note">What changed in the VM, in short: a counted loop and a for-each that end each turn in one instruction, <code>$&gt;</code> <code>$|</code> <code>$&lt;</code> calling their lambda on the VM's own frames, a sort comparator that is a plain comparison evaluated without a call, an assignment written by the instruction that computes it, a text that keeps its character count, a dictionary found by a fast seeded hash, and a call that stopped paying for work it did not need. Nothing in the language changed: every program prints what it printed.</p>
  </div>
</div>

<!-- ═══ METHOD ═══ -->
<div class="install-section" id="method">
  <div class="container">
    <h2>How it was measured</h2>
    <p class="section-sub">One machine, one session: %(cpu)s, %(os)s.</p>
    <div class="dl-table-wrap" style="margin-bottom:1rem">
      <table class="dl-table">
        <thead><tr><th>Language or engine</th><th>Version</th><th>Kind</th></tr></thead>
        <tbody>
            %(vers)s
        </tbody>
      </table>
    </div>
    <ul class="bm-list">
      <li><strong>Twins.</strong> Each program is written once per language with the same algorithm and the same shape as the Python twin, and its printed line is compared with Python's before any figure is kept — %(agree)d of %(total)d agree. Julia's twins put their code inside a <code>main()</code> function: a global in Julia is untyped, and measuring that would measure a use nobody writes.</li>
      <li><strong>Elapsed time</strong> — what whoever runs the program waits — median of %(runs)d runs of the whole process on an otherwise idle machine: start-up, parsing, compiling and running. CPU time was recorded too and agrees with it for the interpreters, which run on one thread; not for the JIT compilers, which compile on other threads while the program starts — Julia used %(jl_cow).1f× as much CPU time as elapsed time. An earlier version of this page showed CPU time, and charged Julia for work no one waits for.</li>
      <li><strong>Start-up subtracted</strong> takes each language's empty-program time off every figure — the reference's too — over the programs Zymbol v0.0.11 takes %(netmin)d ms or more on; on shorter ones, subtracting two close figures would be noise.</li>
      <li><strong>Not a ranking of languages.</strong> Sixteen small programs say how fast an interpreter runs loops, calls, arithmetic, collections and text — not how fast real applications are, which depend on libraries this does not touch.</li>
      <li><strong>v0.0.11 is not released yet.</strong> These are figures of its development branch (commit <code>%(commit)s</code>); the release notes will carry the final ones.</li>
    </ul>
    <div class="code-block" style="margin-top:1rem">
      <span class="cmt"># reproduce — from zyquality/bench/big/</span><br>
      <span class="kw">ZYMBOL_BIN</span>=zymbol <span class="kw">ZYMBOL_OLD</span>=zymbol-0.0.10 python3 langs.py --runs %(runs)d --json out.json
    </div>
  </div>
</div>

''' % dict(
    date=DATE, repo=REPO, nword=WORDS[n_lang], runs=L['runs'], static=static_table(),
    interp_en=en_list(['Zymbol'] + [short[k] for k in interp_others]),
    jl_start=f_ms(start['julia']), jl_net=f_x(net_zy['julia']), js_net=f_x(net_zy['node']),
    rank='%s of the %s interpreters' % (ORD[zy_rank], WORDS[n_interp]),
    lead=en_list(['%s is faster on %d of the sixteen' % (short[k], len(beats[k])) for k in ahead]) if ahead else 'No interpreter is faster in the mean',
    behind=en_list([short[k] for k in behind]),
    rest=(', and still behind one of them on a few programs: ' + '; '.join('%s on %s' % (short[k], ', '.join('<code>%s</code>' % p for p in beats[k])) for k in behind if beats[k])) if any(beats[k] for k in behind) else '',
    net_ahead=en_list(['%s (%s)' % (short[k], f_x(net_zy[k])) for k in net_ahead]) + (' are' if len(net_ahead) > 1 else ' is'),
    sp_tw=speed_tw10, sp_vm=speed_vm10, cpu=html.escape(L['cpu']), os=html.escape(L['os']),
    vers=ver_rows, agree=agree, total=total, evo=evo_table(), jl_cow=cpu_over_wall['julia'], netmin=NET_MIN, commit=COMMIT)

script = JS % {'data': json.dumps(DATA, ensure_ascii=False, separators=(',', ':')).replace('</', '<\\/')}
foot = foot.replace('</body>', script + '</body>')
open(WEB + '/benchmarks.html', 'w').write(top + body + foot)

# ── Markdown twin ────────────────────────────────────────────────────────────
md = []
md.append('# How fast is Zymbol?\n')
md.append('Sixteen programs, %s languages and four Zymbol engines, the same printed answer, measured on %s. One machine, elapsed time per process. Zymbol v0.0.11 is the development branch (commit `%s`); the release is v0.0.10. The HTML page lets the reader pick any language or engine as the reference; this twin carries the figures against Zymbol v0.0.11 = 1.00.\n' % (WORDS[n_lang], DATE, COMMIT))
md.append('The programs, their twins and the script that measured them: %s\n' % REPO)
md.append('## Against Zymbol v0.0.11\n')
md.append('Geometric mean of elapsed time. Whole process: all sixteen programs, start-up included. Start-up subtracted: each language\'s own empty-program time taken off — Zymbol\'s too — over the %d programs Zymbol takes %d ms or more on, still against Zymbol\'s whole process = 1.00.\n' % (len(net_progs), NET_MIN))
md.append('| Language or engine | Kind | Whole process | Start-up subtracted | Its start-up |')
md.append('|---|---|---:|---:|---:|')
for k in ORDER:
    kind_s = 'JIT compiler' if INFO[k][2] == 'jit' else INFO[k][4].replace('`', '')
    name = INFO[k][0] if INFO[k][2] == 'zymbol' else '%s %s' % (INFO[k][0], version(k))
    md.append('| %s | %s | %s | %s | %s ms |' % (name, kind_s, f_x(rel_zy[k]), f_x(net_zy[k]), f_ms(start[k])))
md.append('')
md.append('Zymbol v0.0.11 is %s of the %s interpreters. %s. Zymbol is ahead of %s in the mean. With start-up subtracted, %s ahead of it, and Julia (%s) comes next to JavaScript (%s). PHP\'s opcache JIT is off on the command line and Ruby\'s YJIT is off without `--yjit`, so both run as interpreters.\n' % (
    ORD[zy_rank], WORDS[n_interp],
    en_list(['%s is faster on %d of the sixteen programs' % (short[k], len(beats[k])) for k in ahead]) if ahead else 'No interpreter is faster in the mean',
    en_list([short[k] for k in behind]),
    en_list(['%s (%s)' % (short[k], f_x(net_zy[k])) for k in net_ahead]) + (' are' if len(net_ahead) > 1 else ' is'),
    f_x(net_zy['julia']), f_x(net_zy['node'])))
md.append('## Program by program\n')
md.append('Milliseconds of elapsed time, median of %d runs, start-up included. %d of %d twins printed exactly what the Python twin printed.\n' % (L['runs'], agree, total))
cols = ORDER
md.append('| Program | What it does | ' + ' | '.join(INFO[k][1] + (' (JIT)' if INFO[k][2] == 'jit' else '') for k in cols) + ' |')
md.append('|---|---|' + '---:|' * len(cols))
for p in progs:
    md.append('| `%s` | %s | ' % (p, DESC[p]) + ' | '.join(f_ms(ms[p][k]) for k in cols) + ' |')
md.append('| geometric mean, Zymbol v0.0.11 = 1 | | ' + ' | '.join(f_x(rel_zy[k]) for k in cols) + ' |')
md.append('')
md.append('## From v0.0.10 to v0.0.11\n')
md.append('Zymbol against itself — no other language here. v0.0.10 ran the tree-walker by default; its VM was `zymbol run --vm`. Elapsed milliseconds, median of %d runs; in brackets, against v0.0.11 = 1.00.\n' % L['runs'])
md.append('| Program | v0.0.11 VM | v0.0.10 `--vm` | v0.0.10 tree-walker (its default) |')
md.append('|---|---:|---:|---:|')
for p in progs:
    md.append('| `%s` | ' % p + ' | '.join('%s ms (%s)' % (f_ms(ms[p][k]), f_x(ms[p][k] / ms[p]['zymbol'])) for k in EVO) + ' |')
md.append('| geometric mean | ' + ' | '.join(f_x(gm([ms[p][k] / ms[p]['zymbol'] for p in progs])) for k in EVO) + ' |')
md.append('')
md.append('In elapsed time, v0.0.11 is %.1f× faster than v0.0.10 as it ran by default, and %.1f× faster than v0.0.10\'s VM. Nothing in the language changed: every program prints what it printed.\n' % (speed_tw10, speed_vm10))
md.append('## How it was measured\n')
md.append('%s, %s.\n' % (L['cpu'], L['os']))
md.append('| Language or engine | Version |')
md.append('|---|---|')
for k in ORDER:
    md.append('| %s | %s |' % (INFO[k][0], 'v0.0.11 (development branch, %s)' % COMMIT if k in ('zymbol', 'zymbol_tw') else version(k)))
md.append('')
md.append('- Each program is written once per language with the same algorithm and shape as the Python twin; its printed line is compared with Python\'s before any figure is kept. Julia\'s twins put their code inside a `main()` function, because a global in Julia is untyped.')
md.append('- Elapsed time, median of %d runs of the whole process on an otherwise idle machine. CPU time was recorded too; it agrees for the interpreters, not for the JIT compilers, which compile on other threads — Julia used %.1f× as much CPU time as elapsed time. An earlier version of this page showed CPU time, which charged Julia for work no one waits for.' % (L['runs'], cpu_over_wall['julia']))
md.append('- Not a ranking of languages: sixteen small programs say how fast an interpreter runs loops, calls, arithmetic, collections and text, not how fast real applications are.')
md.append('- v0.0.11 is not released yet; these are figures of its development branch.')
md.append('')
md.append('Reproduce, from `zyquality/bench/big/`: `ZYMBOL_BIN=zymbol ZYMBOL_OLD=zymbol-0.0.10 python3 langs.py --runs %d --json out.json`.' % L['runs'])
open(WEB + '/benchmarks.md', 'w').write('\n'.join(md) + '\n')
print('ok', {k: round(rel_zy[k], 3) for k in ORDER}, 'net', {k: round(net_zy[k], 3) for k in ORDER},
      'tw10', round(speed_tw10, 2), 'vm10', round(speed_vm10, 2))
