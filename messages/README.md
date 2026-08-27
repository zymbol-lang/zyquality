# The diagnostic inventory

## Why this exists

Comparing engines by running the corpus only finds the messages the corpus
happens to trigger. That found about thirty differences. The engines between
them define **several hundred** messages, and the ones no test reaches are
exactly the ones that will be wrong when a user finally reaches them — because
most are reached only by a malformed program, and a corpus is made of programs
that run.

`extract.py` reads the **source** instead: every string that is prose addressed
to a reader, in all three engines, whether or not any test has ever hit it.

```bash
python3 zyquality/messages/extract.py              # the counts
python3 zyquality/messages/extract.py --only-js    # what zyjs says and Rust does not
python3 zyquality/messages/extract.py --only-rust  # and the reverse
python3 zyquality/messages/extract.py --same       # what already matches
```

It cannot tell that two differently worded messages describe the same
situation — that judgement is a person's. What it can do is put them side by
side and be exhaustive about it, which is the part a person cannot do by hand.

## En el gate desde el 2026-08-26, con línea base

Estaba escrito y **no lo corría nadie**: `zyq suite` no lo conocía, y el script
resolvía `interpreter/crates` literalmente, así que solo funcionaba desde la raíz
del workspace y moría en cualquier otro sitio. Un medidor que nadie ejecuta se
pudre; éste medía 1183 diferencias y llevaba meses callado.

```bash
python3 zyquality/messages/extract.py             # compara contra baseline.txt
python3 zyquality/messages/extract.py --baseline  # regraba (deliberadamente)
./zyq suite --only messages                       # lo mismo, dentro del gate
```

**La cifra que importa es la superficie COMPARTIDA.** Rust implementa cosas que
`zymbol.js` no tiene ni debe tener —el CLI, el REPL, el empaquetador, el
formateador, el LSP, el compilador, la VM— y un mensaje de ahí no es una
divergencia. Sólo lexer, parser, semántico, intérprete, common, ast y error se
comparan, y sólo un mensaje nuevo **ahí** pone el gate en rojo.

Estado al registrarlo: **804 de un solo lado en superficie compartida** (741 sólo
Rust, 63 sólo zyjs), más 381 en superficie que zyjs no implementa.

### Lo que esta medida NO es

Una lista de 804 bugs. Es el **denominador**: cuántos sitios hay donde los dos
motores pueden discrepar y nadie ha mirado. Baja cuando se porta un mensaje;
sube cuando alguien añade uno a un solo motor.

⚠ **Cerca del 30 % de las entradas no tienen forma de frase.** Parte son
mensajes reales que ningún filtro simple reconoce (`'§' was declared at §:§`),
parte son fixtures de Zymbol dentro de doc-comments que `is_message` deja pasar.
No rompe el trabajo del medidor —sigue siendo monótono y sigue cazando altas—
pero el 804 está inflado en esa proporción. Afinar `is_message` **bajará** la
línea base, y eso es una mejora, no una rotura.

### Un tercer fallo del escáner, del mismo tipo que los dos de abajo

`'"'` es un literal de carácter perfectamente normal en Rust, y el escáner leía
su comilla interior como **apertura de cadena**, tragándose el código fuente
hasta la siguiente. Un lexer está lleno de `'"'`, así que el crate más afectado
era justo `zymbol-lexer`. Ahora los literales de carácter se saltan enteros.

## Two mistakes the script exists to not repeat

**Anchoring on constructor names.** The first version harvested only literals
following `Diagnostic::error(`, `new ZyError(` and friends. It missed every
message built inside a helper — `tuple_immutable_msg`, `missing_key_msg` —
which are precisely the ones that were unified by hand and most deserve
checking. It reported `cannot modify tuple` as existing in the browser engine
and not in Rust, which is the opposite of true.

**Regex to the first placeholder.** `format!("expected {}, got {}")` and
`` `expected ${a}, got ${b}` `` are the same message, but a pattern that stops
at the first `{` splits them. That produced 54 false differences.

Both failures share a shape, and it is the one this whole directory is about: a
measurement that is wrong in the direction of *more* differences sends someone
to "fix" an engine that was already right.

## The triage — 2026-08-19

52 messages exist in the browser engine and not in Rust. They are not one
problem:

### A · Correctly engine-specific — leave them

A browser tab needs limits a command line does not, and the playground has no
filesystem, no ODBC and no module resolver of its own.

```
Execution limit reached (… steps) — infinite loop?
Infinite loop limit reached (…) — add @! to break
Output limit reached (… KB) — infinite loop?
Cannot import '…': no module resolver available
standard library module 'std/db' is not available in the web playground (requires ODBC)
```

### B · Structural — the same content, laid out differently

Rust puts guidance on its own `help:` line; the browser engine folds it into the
message after an em dash. Same words, different shape, and every one of these
shows as a difference:

```
rust   error: imports must come before any statement
         help: move this `<#` above the first statement
zyjs   error: imports must come before any statement — move this `<#` above …
```

Fixing this once — a `help` field on the browser engine's diagnostic, printed
the way Rust prints it — closes about nine of them at a stroke.

One is a single word: the browser engine says `hint:` in one message where every
other message in all three engines says `help:`.

### C · The same rule, different words — the actual work

About thirty. Each needs a person to pick the better wording, and the better one
is not always Rust's:

```
zyjs   expected expression, found == — '>>' takes arithmetic; parenthesise a comparison
rust   expected expression, found Eq                          ← Rust names a token kind
```

```
zyjs   Index 0 is invalid (indices start at 1)
rust   index 0 is invalid — Zymbol uses 1-based indexing (use 1 for the first
       element, -1 for the last)                              ← Rust is better here
```

The browser engine also capitalises the first word where Rust never does
(`Cannot iterate`, `Index 0`, `Unknown field`), which is mechanical.

## What this does not cover yet

The Rust side over-collects: 1184 harvested strings include prose that is not a
diagnostic. The `--only-rust` list is therefore a lead, not a verdict. Narrowing
it needs the harvest to know which literals reach a user, which means following
them to a constructor — the thing the first version tried and got wrong for the
opposite reason. Until then, the `--only-js` direction is the reliable one.

## What it found first — 2026-08-19

Two things the corpus could not have found, both traced to the harness rather
than to an engine:

**The `(line N)` suffix and a flush-left `help:`.** `web/tests/run_one.mjs`
appended the line number to the message text — on a message with guidance it
landed after the guidance, reading as if the number belonged to the advice — and
printed `help:` without the two-space indent the CLI uses. Neither came from the
engine: `zymbol.js` has no message with a line number in it, and the playground
reads `d.line` as a field. Fixed; the harness now prints the CLI's shape.

**Nine warnings that nobody printed.** The same file kept only
`severity === 'error'`, so every warning the browser engine computed was dropped.
With them emitted, the engines turn out to disagree about **which** warnings to
raise, not merely how to word them: 3 identical, 1 missing in the browser,
9 raised there and not in Rust, and 4 where the two engines choose a different
diagnostic for the same code. Fourteen divergences, none reachable by a corpus —
a corpus is made of programs that run and whose output is compared.

That is the argument for reading the source rather than waiting for a test to
trip: the messages a test never reaches are the ones nothing is defending.

## The cascade — found the same way, 2026-08-19

Lining the engines up message by message showed one probe reporting **22 errors**
for a single bad line, and another 17. Only the first was real; the rest were the
parser reading the tail of the statement it had just refused, each fragment
producing its own `unexpected token: X` with a `help:` listing every statement
keyword.

The cause was recovery: `parse_block` and the top-level loop advanced by **one
token** after a failed statement — enough to make progress, not enough to get
past the statement that failed. They now skip to the end of it (`skip_statement`,
which always advances at least once, or recovery becomes a loop).

```text
before   error: unexpected '(' at statement level
           help: use '(a, b) = expr' for tuple destructuring
         error: unexpected token: Comma          ← the parser's own leftovers
           help: expected statement (>>, <<, ?, ??, @, …)
         error: unexpected token: RParen         ← and again
           help: expected statement (>>, <<, ?, ??, @, …)

after    error: unexpected '(' at statement level
           help: use '(a, b) = expr' for tuple destructuring
```

Regenerating the goldens deleted **386 lines and added 4**: the corpus had been
remembering the noise. 22 → 1 on the worst case, 17 → 6 on a multi-line one.

Worth naming the shape: this was never a *difference between engines* — the
browser engine stopped at the first error and was right to. It surfaced because
comparing the two forced someone to read both outputs in full, which nobody does
when a test merely passes.

## Two more, found the same way — 2026-08-19

**Non-deterministic diagnostics.** Enabling def-use in `zymbol run` made the
formatter audit report 13 failures twice in a row **with different files among
them**. The cause was not the audit: `get_ambiguous_variables()` walks a HashMap,
so one file reported `'k'` before `'w'` on one run and after it on the next. A
diagnostic whose ORDER changes between runs makes every differential comparison
flap. Both call sites now sort by source position, and two consecutive audit runs
are identical.

That bug had been in `zymbol check` since the warning existed. It only became
visible when a second command started printing the same thing.

**`zymbol fmt` refused any file using the new syntax.** `#[…]` and
`@ (k, v):pares` had no formatter support, and the safety gate did its job:
rather than print `[…]` for `#[…]` — a different program, since the homogeneity
check applies to one and not the other — it refused to write the file. Both are
supported now, and the pattern printer is shared with the destructure assignment
rather than copied.

**Still open, and pre-existing:** the formatter adds a blank line on every pass
when a one-line `?? { … }` sits inside `>> ( … )`. A file that grows each time
you format it is a real defect; it is not caused by anything here, and
`corpus/match/20_list_pattern_compares.zy` was written multi-line to stop
tripping it rather than to hide it.
