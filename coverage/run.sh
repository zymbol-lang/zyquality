#!/usr/bin/env bash
# Which parts of the interpreter has the corpus never executed?
#
# `zyq consensus` and `zyq expect` answer whether the engines agree on the
# programs we wrote. Neither can answer the question this script asks: what
# code no test has ever reached. That is the only measurement that finds a gap
# nobody thought of — a corpus is written from what its author understands, and
# what its author understands is exactly where the bugs are not.
#
# Not registered in suites.toml on purpose. It needs a separate instrumented
# build, takes minutes, and its output is a list to read rather than a verdict
# to gate on. Run it when adding a test area, not on every change.
#
#   bash coverage/run.sh              # measure and report
#   bash coverage/run.sh --html       # also write an HTML report
#   bash coverage/run.sh --keep       # keep the profile data for llvm-cov show
#
# Requires: rustup component add llvm-tools-preview

set -uo pipefail

ZQ_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
INTERP="${ZYMBOL_SRC:-$ZQ_DIR/../interpreter}"
OUT="${ZY_COV_DIR:-$HOME/.cache/zymbol-coverage}"
WANT_HTML=0
KEEP=0
for a in "$@"; do
    case "$a" in
        --html) WANT_HTML=1 ;;
        --keep) KEEP=1 ;;
        -h|--help) sed -n '2,20p' "$0"; exit 0 ;;
        *) echo "unknown option: $a" >&2; exit 2 ;;
    esac
done

if [ ! -d "$INTERP/crates" ]; then
    echo "coverage: no interpreter checkout at $INTERP (set ZYMBOL_SRC)" >&2
    exit 2
fi

TOOLS="$(rustc --print target-libdir 2>/dev/null)/../bin"
PROFDATA="$TOOLS/llvm-profdata"
LLVMCOV="$TOOLS/llvm-cov"
if [ ! -x "$PROFDATA" ] || [ ! -x "$LLVMCOV" ]; then
    echo "coverage: llvm-profdata/llvm-cov not found in $TOOLS" >&2
    echo "          rustup component add llvm-tools-preview" >&2
    exit 2
fi

# The crates the corpus cannot reach by construction, and that have suites of
# their own. Counting them would report a number that no corpus file could ever
# improve, which is worse than not reporting one.
#   analyzer/lsp  the language server: driven by an editor, not by a .zy file
#   repl          interactive line editing
#   package       .zyp archives, covered by web/tests/test_zyp.mjs
#   standalone    `zymbol build`, which shells out to cargo
EXCLUDE='(/\.cargo/|/rustc/|zymbol-analyzer|zymbol-repl|zymbol-package|zymbol-standalone|zymbol-lsp)'

echo "── building instrumented binary ─────────────────────────────"
( cd "$INTERP" && RUSTFLAGS="-C instrument-coverage" cargo build --profile dev 2>&1 | tail -1 )
BIN="$INTERP/target/debug/zymbol"
[ -x "$BIN" ] || { echo "coverage: build produced no binary" >&2; exit 2; }

rm -rf "$OUT"; mkdir -p "$OUT"
# %8m is LLVM's merge pooling: eight files that concurrent processes merge into,
# rather than one profraw per process. Without it 594 files × 4 modes wrote 2376
# raw profiles and filled a 7 GB tmpfs.
export LLVM_PROFILE_FILE="$OUT/zy-%8m.profraw"

echo "── running the corpus through run / --vm / check / fmt ──────"
cd "$ZQ_DIR"
n=0
while IFS= read -r f; do
    timeout 10 "$BIN" run      "$f" >/dev/null 2>&1
    timeout 10 "$BIN" run --vm "$f" >/dev/null 2>&1
    timeout 10 "$BIN" check    "$f" >/dev/null 2>&1
    timeout 10 "$BIN" fmt      "$f" >/dev/null 2>&1
    n=$((n + 1))
done < <(find corpus -name '*.zy' | sort)
echo "   $n corpus files × 4 entry points"

"$PROFDATA" merge -sparse "$OUT"/*.profraw -o "$OUT/zy.profdata" || exit 2

echo
echo "── coverage, worst first ────────────────────────────────────"
"$LLVMCOV" report "$BIN" -instr-profile="$OUT/zy.profdata" \
    -ignore-filename-regex="$EXCLUDE" 2>/dev/null \
  | awk 'NF>=7 && $1!="Filename" {gsub(/.*crates\//,"",$1); if ($1!="TOTAL") printf "%8d uncovered  %7s  %s\n", $3, $4, $1}' \
  | sort -rn | head -15
echo
"$LLVMCOV" report "$BIN" -instr-profile="$OUT/zy.profdata" \
    -ignore-filename-regex="$EXCLUDE" 2>/dev/null | grep '^TOTAL' \
  | awk '{printf "   TOTAL  %s of regions covered, %s of lines\n", $4, $10}'

# ── Which bytecode instructions never ran ───────────────────────────────────
# The VM's dispatch loop is one match over ~126 instructions, so "which arms
# never executed" is directly a list of language constructs no test reaches.
#
# An instruction the compiler never emits is dead code to delete, not a test to
# write, so the two are told apart — but only as a hint. There is no bytecode
# dump to ask, and the compiler mentions instructions in three ways: it emits
# them (`emit(Instruction::X(`, `push(Instruction::X(`, `Some(Instruction::X(`)
# and it also *matches* on them in register-liveness analysis. Counting every
# mention called StrSplit emitted when the mention was a match arm; counting
# only `emit(` called Or dead when it is emitted through `push`. The patterns
# below cover the three emission forms in the tree today — confirm before
# deleting anything.
echo
echo "── bytecode instructions the corpus never executed ──────────"
"$LLVMCOV" show "$BIN" -instr-profile="$OUT/zy.profdata" --format=text \
    -show-line-counts "$INTERP/crates/zymbol-vm/src/lib.rs" 2>/dev/null > "$OUT/vm_show.txt"

instr_of() { awk -F'|' -v want="$1" '
    (want=="dead"  && $2 ~ /^ *0 *$/) || (want=="live" && $2 !~ /^ *0 *$/) {
        if (match($3, /Instruction::[A-Za-z]+/))
            print substr($3, RSTART+13, RLENGTH-13)
    }' "$OUT/vm_show.txt" | sort -u; }

comm -23 <(instr_of dead) <(instr_of live) > "$OUT/never_run.txt"
if [ ! -s "$OUT/never_run.txt" ]; then
    echo "   none — every arm of the dispatch loop is reached"
else
    while IFS= read -r ins; do
        emitted=$(grep -rhoE "(emit|push|Some)\(Instruction::$ins\(" \
                       "$INTERP/crates/zymbol-compiler/src" 2>/dev/null | wc -l)
        if [ "$emitted" -eq 0 ]; then
            printf "   %-18s probably DEAD — no emission site found; confirm, then delete\n" "$ins"
        else
            printf "   %-18s GAP — emitted in %s place(s), but no corpus file runs it\n" "$ins" "$emitted"
        fi
    done < "$OUT/never_run.txt"
fi

# ── What kind of code is unreached ──────────────────────────────────────────
# Reported because the answer has been the same every time it was asked: error
# paths. A corpus grows by adding programs that work.
echo
echo "── unreached lines in the VM, by kind ───────────────────────"
awk -F'|' '$2 ~ /^ *0 *$/ {print $3}' "$OUT/vm_show.txt" > "$OUT/vm_dead.txt"
printf "   %-28s %s\n" "total unreached lines" "$(wc -l < "$OUT/vm_dead.txt")"
for pat in 'VmError::' 'raise!' 'TypeError' 'return Err' 'unreachable\|unimplemented'; do
    printf "   %-28s %s\n" "$pat" "$(grep -c "$pat" "$OUT/vm_dead.txt")"
done

if [ "$WANT_HTML" -eq 1 ]; then
    "$LLVMCOV" show "$BIN" -instr-profile="$OUT/zy.profdata" -format=html \
        -ignore-filename-regex="$EXCLUDE" -output-dir="$OUT/html" 2>/dev/null
    echo
    echo "   HTML report: $OUT/html/index.html"
fi

if [ "$KEEP" -eq 1 ]; then
    echo
    echo "   profile kept at $OUT/zy.profdata — inspect one file with:"
    echo "     $LLVMCOV show \$BIN -instr-profile=$OUT/zy.profdata --format=text \\"
    echo "       -show-line-counts <path/to/file.rs> | grep -n '^ *[0-9]* *| *0 *|'"
else
    rm -f "$OUT"/*.profraw
fi
