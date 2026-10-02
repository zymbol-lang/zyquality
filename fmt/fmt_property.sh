#!/usr/bin/env bash
# fmt_property.sh — Property-based audit of `zymbol fmt` over the .zy corpus.
#
# Verifies four properties on every test/example file:
#   P1 reparse      — formatted output must still pass `zymbol check`
#   P2 idempotence  — fmt(fmt(x)) == fmt(x)
#   P3 semantics    — formatted program produces identical runtime output
#   P4 comments     — `//` and `/*` token counts are preserved
#
# Files are formatted via an in-place swap (original backed up and always
# restored) so module-name checks and relative imports stay valid.
#
# The corpus lives in ZyQuality (../zyquality), the project's point of record
# for testing; this repository's own `examples/` are swept too.  This script
# stays here rather than moving with the corpus because it tests a *feature of
# one engine* — only the Rust build has a formatter — and there is nothing
# differential about it.  What moved is the files it reads.
#
# NOTE: it writes to the corpus in place while it works, and restores each file
# afterwards.  Run it on a clean checkout, and check `git -C ../zyquality status`
# if it is ever interrupted.
#
# What it EXECUTES runs somewhere else.  P3 used to run every program from the
# caller's directory — the root of this repository when `zyq suite` drives it —
# so a program that writes a file wrote it here: `corpus/i18n/test_database.zy`
# left a file called `25` behind (a `>` in its SQL reached the shell), and the
# std/db tests left their databases.  Each run now gets a scratch directory of
# its own, the way zyq runs every engine.  And a program corpus.toml excuses
# from the tree-walker is not executed at all: the table says it cannot be
# judged, and that is as true for the formatter's P3 as for a golden.  The
# table is read through `zyq excused` — one reader, not two.
#
# Usage:
#   ./fmt/fmt_property.sh                                # report all failures
#   ./fmt/fmt_property.sh --baseline fmt/baseline.txt    # regressions only
#   ./fmt/fmt_property.sh --update-baseline fmt/baseline.txt

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ZYQ_HOME="$(cd "$SCRIPT_DIR/.." && pwd)"
TESTS_DIR="$ZYQ_HOME/corpus"

# The interpreter's own examples are swept too when that checkout is present:
# they are 98 more real programs, and the formatter has no reason to care which
# repository a file came from.  Absent, the corpus alone is plenty.
EXAMPLES_DIR="${ZY_EXAMPLES:-$ZYQ_HOME/../interpreter/examples}"
# Absolute: programs run from a scratch directory, so a relative path would
# point at nothing there.
if [[ -d "$EXAMPLES_DIR" ]]; then EXAMPLES_DIR="$(cd "$EXAMPLES_DIR" && pwd)"; else EXAMPLES_DIR=""; fi

# corpus.toml is read by zyq and only by zyq. Without it this script cannot know
# which programs must not be run, and running them anyway is the defect above —
# so its absence is "could not run" (2), never a silent pass.
ZYQ="$ZYQ_HOME/zyq"
[[ -x "$ZYQ" ]] || { echo "fmt_property.sh: build zyq first: make -C '$ZYQ_HOME'" >&2; exit 2; }
declare -A NOT_RUN=()
while IFS= read -r rel_excused; do
    [[ -n "$rel_excused" ]] && NOT_RUN["corpus/$rel_excused"]=1
done < <("$ZYQ" --root "$ZYQ_HOME" excused --engines zytw)

# Only one engine has a formatter, so this suite is not differential -- but it
# is a language-quality property over the shared corpus, which is why it lives
# here rather than beside that engine.
ZYMBOL="${ZYMBOL_BIN:-zymbol}"
command -v "$ZYMBOL" >/dev/null 2>&1 || [[ -x "$ZYMBOL" ]] || {
    echo "fmt_property.sh: interpreter not found: $ZYMBOL" >&2
    echo "  install it, or set ZYMBOL_BIN to a build." >&2
    exit 2
}
TIMEOUT_SEC=10

BASELINE=""
UPDATE_BASELINE=""
if [[ "${1:-}" == "--baseline" ]]; then BASELINE="${2:?--baseline needs a file}"; fi
if [[ "${1:-}" == "--update-baseline" ]]; then UPDATE_BASELINE="${2:?--update-baseline needs a file}"; fi

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
RESET='\033[0m'

PASS=0; SKIP=0; FAILED_FILES=0; P3_EXCUSED=0
declare -a FAILURES=()   # entries: "P1 rel", "P2 rel", "P3 rel", "P4 rel"
declare -a SKIPPED=()

WORK="$(mktemp -d)"
CURF=""
restore() { if [[ -n "$CURF" && -f "$WORK/cur" ]]; then cp "$WORK/cur" "$CURF"; fi; rm -rf "$WORK"; }
trap restore EXIT

# Diagnostics legitimately shift line/col after formatting; normalize spans.
normalize_spans() { sed -E 's/:[0-9]+:[0-9]+/:L:C/g'; }

run_file() { # $1 = absolute .zy path; its .input is stdin and its .keys the key script
    local input_file="${1%.zy}.input" keys_file="${1%.zy}.keys" here
    local -a keys=()
    [[ -f "$keys_file" ]] && keys=(--keys "$keys_file")
    [[ -f "$input_file" ]] || input_file=/dev/null
    # A fresh directory per run, like zyq's sandbox: what a program writes lands
    # there, and a second run cannot read what the first one left behind.
    here="$(mktemp -d "$WORK/run.XXXXXX")"
    (cd "$here" && timeout "$TIMEOUT_SEC" "$ZYMBOL" run ${keys[@]+"${keys[@]}"} "$1" < "$input_file" 2>&1) \
        | normalize_spans
    rm -rf "$here"
    return 0
}

mapfile -t FILES < <(
    find "$TESTS_DIR" ${EXAMPLES_DIR:+"$EXAMPLES_DIR"} -name "*.zy" \
        2>/dev/null | sort
)

TOTAL=${#FILES[@]}
echo -e "${BOLD}═══════════════════════════════════════════════════════════${RESET}"
echo -e "${BOLD}  Zymbol Formatter Property Report — $TOTAL files${RESET}"
echo -e "${BOLD}═══════════════════════════════════════════════════════════${RESET}"
echo ""

for file in "${FILES[@]}"; do
    rel="${file#$ZYQ_HOME/}"

    # Only files whose ORIGINAL passes `check` are meaningful for the
    # formatter contract (negative tests expect lexer/parser/semantic errors).
    if ! "$ZYMBOL" check "$file" >/dev/null 2>&1; then
        SKIP=$((SKIP + 1)); SKIPPED+=("$rel (original fails check)")
        continue
    fi

    # fmt output goes straight to a file: command substitution would drop
    # NUL bytes (TUI sources legitimately contain them in char literals)
    if ! "$ZYMBOL" fmt "$file" > "$WORK/fmt1" 2>"$WORK/err"; then
        # Formatter refused a valid file — count as a P1-class failure.
        FAILURES+=("P1 $rel"); FAILED_FILES=$((FAILED_FILES + 1))
        echo -e "  ${RED}FAIL${RESET}  $rel  ${RED}[fmt error: $(head -c 120 "$WORK/err" | tr -d '\n')]${RESET}"
        continue
    fi

    file_failed=false
    # P3 inconclusive. Not a pass: the file was counted as PASS *and* SKIP until
    # 2026-10-02, so PASS + SKIP came out larger than the number of files.
    file_skipped=false

    # P2 — idempotence (via stdin, no swap needed)
    "$ZYMBOL" fmt - < "$WORK/fmt1" > "$WORK/fmt2" 2>/dev/null
    if ! cmp -s "$WORK/fmt1" "$WORK/fmt2"; then
        FAILURES+=("P2 $rel"); file_failed=true
        echo -e "  ${RED}FAIL${RESET}  $rel  ${RED}[P2 not idempotent]${RESET}"
    fi

    # P4 — comment token counts
    c1=$(grep -ao '//' "$file" | wc -l);  c2=$(grep -ao '//' "$WORK/fmt1" | wc -l)
    b1=$(grep -ao '/\*' "$file" | wc -l); b2=$(grep -ao '/\*' "$WORK/fmt1" | wc -l)
    if [[ "$c1" -ne "$c2" || "$b1" -ne "$b2" ]]; then
        FAILURES+=("P4 $rel"); file_failed=true
        echo -e "  ${RED}FAIL${RESET}  $rel  ${RED}[P4 comments //:$c1->$c2 /*:$b1->$b2]${RESET}"
    fi

    # P1 + P3 — swap formatted content in place, test, restore
    has_expected=false
    [[ -f "${file%.zy}.expected" ]] && has_expected=true
    # Excused from the tree-walker in corpus.toml: formatted and reparsed like
    # any other file, never executed (see the NOTE at the top).
    if $has_expected && [[ -n "${NOT_RUN[$rel]:-}" ]]; then
        has_expected=false; P3_EXCUSED=$((P3_EXCUSED + 1))
    fi
    o1=""
    if $has_expected; then o1="$(run_file "$file")"; fi

    CURF="$file"
    cp "$file" "$WORK/cur"
    cp "$WORK/fmt1" "$file"

    if ! "$ZYMBOL" check "$file" >/dev/null 2>&1; then
        FAILURES+=("P1 $rel"); file_failed=true
        echo -e "  ${RED}FAIL${RESET}  $rel  ${RED}[P1 reparse]${RESET}"
    elif $has_expected; then
        o2="$(run_file "$file")"
        if [[ "$o1" != "$o2" ]]; then
            # Nondeterminism guard: rerun the original before blaming fmt.
            cp "$WORK/cur" "$file"
            o1b="$(run_file "$file")"
            cp "$WORK/fmt1" "$file"
            if [[ "$o1" != "$o1b" ]]; then
                SKIP=$((SKIP + 1)); SKIPPED+=("$rel (nondeterministic output)")
                file_skipped=true
            else
                FAILURES+=("P3 $rel"); file_failed=true
                echo -e "  ${RED}FAIL${RESET}  $rel  ${RED}[P3 semantics]${RESET}"
            fi
        fi
    fi

    cp "$WORK/cur" "$file"
    CURF=""

    if $file_failed; then
        FAILED_FILES=$((FAILED_FILES + 1))
    elif ! $file_skipped; then
        PASS=$((PASS + 1))
    fi
done

echo ""
echo -e "${BOLD}═══════════════════════════════════════════════════════════${RESET}"
echo -e "${BOLD}  SUMMARY${RESET}"
echo -e "${BOLD}═══════════════════════════════════════════════════════════${RESET}"
echo -e "  Total files  : ${BOLD}$TOTAL${RESET}"
echo -e "  ${GREEN}PASS${RESET}         : ${GREEN}${BOLD}$PASS${RESET}"
echo -e "  ${RED}FAIL${RESET}         : ${RED}${BOLD}$FAILED_FILES${RESET} file(s), ${#FAILURES[@]} property failure(s)"
echo -e "  ${YELLOW}SKIP${RESET}         : ${YELLOW}${BOLD}$SKIP${RESET}"
for p in P1 P2 P3 P4; do
    n=$(printf '%s\n' "${FAILURES[@]:-}" | grep -c "^$p " || true)
    echo -e "    $p failures : $n"
done
echo -e "  P3 not run   : $P3_EXCUSED (excused from the tree-walker in corpus.toml)"
echo ""

# Grading the grader: every file is exactly one of pass, skip or fail. A total
# that does not add up is a defect in this script, and no verdict it gives can
# be trusted — which is what the double count above had been doing quietly.
if (( PASS + SKIP + FAILED_FILES != TOTAL )); then
    echo -e "${RED}${BOLD}fmt_property.sh: $PASS + $SKIP + $FAILED_FILES ≠ $TOTAL — the tally is wrong${RESET}" >&2
    exit 2
fi

if [[ -n "$UPDATE_BASELINE" ]]; then
    printf '%s\n' "${FAILURES[@]:-}" | grep -v '^$' | sort > "$UPDATE_BASELINE"
    echo -e "${CYAN}Baseline written to $UPDATE_BASELINE ($(wc -l < "$UPDATE_BASELINE") entries)${RESET}"
    exit 0
fi

if [[ -n "$BASELINE" ]]; then
    new_failures="$(printf '%s\n' "${FAILURES[@]:-}" | grep -v '^$' | sort | comm -23 - <(sort "$BASELINE"))"
    if [[ -n "$new_failures" ]]; then
        echo -e "${RED}${BOLD}NEW failures not in baseline:${RESET}"
        echo "$new_failures" | sed 's/^/  ✗ /'
        exit 1
    fi
    fixed="$(printf '%s\n' "${FAILURES[@]:-}" | grep -v '^$' | sort | comm -13 - <(sort "$BASELINE"))"
    if [[ -n "$fixed" ]]; then
        echo -e "${GREEN}Fixed since baseline (consider --update-baseline):${RESET}"
        echo "$fixed" | sed 's/^/  ✓ /'
    fi
    echo -e "${GREEN}${BOLD}No regressions vs baseline.${RESET}"
    exit 0
fi

if [[ ${#FAILURES[@]} -eq 0 ]]; then
    echo -e "${GREEN}${BOLD}All $PASS files satisfy P1–P4!${RESET}"
    exit 0
else
    echo -e "${RED}${BOLD}${#FAILURES[@]} property failures.${RESET}"
    printf '%s\n' "${FAILURES[@]}" | sed 's/^/  ✗ /'
    exit 1
fi
