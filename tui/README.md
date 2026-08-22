# TUI tests

`<<|` and `<<|?` cannot be tested through a pipe: they need a real terminal, and
a program reading from a pipe never reaches raw mode at all.  `ptydrive.py`
allocates a pty and feeds keystrokes as the program asks for them.

**Run them as a suite** — this is the gate, and it compares the engines for you:

```bash
bash tui/run.sh                    # every case, every engine with a terminal
bash tui/run.sh -v                 # name the cases that agree too
./zyq suite --only tui             # the same thing, through zyq
```

By hand, one engine at a time:

```bash
python3 tui/ptydrive.py zymbol run       tui/keys_blocking.zy -- 'x' '\x1b[A' 'z'
python3 tui/ptydrive.py zymbol run --vm  tui/keys_blocking.zy -- 'x' '\x1b[A' 'z'
```

The outputs must be byte-identical, escape sequences included.

> This file used to give exactly two commands to type by hand, one of them
> `./zyml run`, and the sentence above — with nothing checking that the outputs
> matched. `run.sh` is that check. zyml, the OCaml engine those commands
> compared against, was retired on 2026-08-17; both remaining engines come from
> the same binary, so this is now a tree-walker/VM comparison rather than a
> cross-implementation one, and byte-identical TUI output through a pty was the
> last thing zyml still won on outright.

Keys are sent **interleaved** with reading, not up front.  A program that has
not yet put the terminal into raw mode is still line-buffered, so anything sent
before that point is echoed by the terminal instead of reaching the program —
which is what made the first version of this driver hang.

`keys_blocking.zy` covers `<<|` and arrow decoding; `keys_polling.zy` covers
`<<|?` inside a game loop, together with `>>!`, `>>~` and `@~`;
`keys_control.zy` covers Ctrl+letter, Tab, Backspace, ESC, Enter and a
multi-byte grapheme.

## Agreement is not enough — cases may carry a golden

A case with a `<base>.expected` beside it is compared against that file as well
as against the other engines, and a mismatch is reported as **stale**, counted
apart from a divergence and failing the suite just the same.

Both checks are needed and they catch different things. A divergence means one
engine is wrong. A stale golden means the engines still agree and what they
agree on has changed — **the only way a fault both engines share can ever
surface here.** BUG-ZYB-006 was exactly that: `<<|` handed back Ctrl+A as the
letter `a`, and Tab and Backspace as one indistinguishable NUL, in the
tree-walker *and* in the VM. This harness called that agreement for as long as
it existed, and was right to: they did agree. Nobody was asking whether what
they agreed on was true.

Record one by running the case and reading the result before you keep it:

```bash
python3 tui/ptydrive.py zymbol run tui/keys_control.zy \
    -- '\x01' '\x03' '\x08' '\x09' '\x7f' '\x1b' '\r' 'ñ' > tui/keys_control.expected
```

The keystrokes for a case live in `keys_for()` in `run.sh` — which keys, and in
which order, is part of the test and not a detail of running it.
