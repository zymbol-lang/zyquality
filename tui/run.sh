#!/usr/bin/env bash
# tui/run.sh — key input and raw mode, through a real terminal, on every engine.
#
#   bash tui/run.sh              # every case, every installed engine
#   bash tui/run.sh -v           # name the cases that agree too
#
# Why this cannot be `zyq consensus`
# ----------------------------------
# `<<|` and `<<|?` need a real terminal. A program reading from a pipe never
# reaches raw mode at all, so `zyq`, which gives every engine a file descriptor,
# structurally cannot exercise them — it would compare two programs that both
# gave up at the same place. `ptydrive.py` allocates a pty and feeds keystrokes
# as the program asks for them.
#
# That is also why this had never run in a gate. The driver and its two cases
# lived in zyml/tests/, documented with a pair of commands to type by hand and
# the sentence "the two outputs must be byte-identical" — with nothing checking
# that they were, and only two of the four engines named.
#
# Keys are sent *interleaved* with reading, not up front: a program that has not
# yet entered raw mode is still line-buffered, and anything sent before that
# point is echoed by the terminal instead of reaching the program. That is what
# made the first version of the driver hang.
#
# Exit status: 0 the engines agree, 1 they do not, 2 could not run.

set -uo pipefail

TUI_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ZYQ_HOME="$(cd "$TUI_DIR/.." && pwd)"

RED=$'\033[0;31m'; GREEN=$'\033[0;32m'; YELLOW=$'\033[1;33m'
DIM=$'\033[2m'; BOLD=$'\033[1m'; RESET=$'\033[0m'

VERBOSE=0
for a in "$@"; do case "$a" in -v|--verbose) VERBOSE=1 ;; esac; done

command -v python3 >/dev/null 2>&1 || {
    echo "tui/run.sh: python3 is required to allocate a pty" >&2; exit 2; }

# ── Engines ───────────────────────────────────────────────────────────────────
# Named here rather than read from engines.toml because a pty run is not a
# `{file}` substitution: the driver needs argv split into program and arguments,
# and only the engines that can reach raw mode at all are candidates. The
# JavaScript engine runs in a browser and has no terminal to put into raw mode.
declare -a NAMES=() CMDS=()
ZYMBOL="${ZYMBOL_BIN:-zymbol}"
if command -v "$ZYMBOL" >/dev/null 2>&1 || [[ -x "$ZYMBOL" ]]; then
    NAMES+=(zytw); CMDS+=("$ZYMBOL run")
    NAMES+=(zyvm); CMDS+=("$ZYMBOL run --vm")
fi

# zyml was the third engine here until 2026-08-17; it is retired, and its
# byte-identical TUI output through a pty was the last thing it still won on.
# The two remaining candidates both come from the same binary, so this is now a
# tree-walker/VM comparison rather than a cross-implementation one.
if [[ ${#NAMES[@]} -lt 2 ]]; then
    echo "tui/run.sh: need at least two engines that can reach raw mode; found: ${NAMES[*]:-none}" >&2
    echo "  set ZYMBOL_BIN, or build the interpreter." >&2
    exit 2
fi

# ── Cases ─────────────────────────────────────────────────────────────────────
# Keystrokes per case, because they are part of the test: which keys, and in
# which order, is what the program is being asked about.
keys_for() {
    case "$1" in
        keys_blocking) printf '%s\n' 'x' '\x1b[A' 'z' ;;
        keys_polling)  printf '%s\n' 'a' '\x1b[B' 'q' ;;
        # Ctrl+A, Ctrl+C, Ctrl+H, Tab, Backspace, ESC, Enter, ñ — the keys
        # BUG-ZYB-006 was about, plus the three that already worked, so a fix
        # that broke those would show up here too.
        keys_control)  printf '%s\n' '\x01' '\x03' '\x08' '\x09' '\x7f' '\x1b' '\r' 'ñ' ;;
        *)             printf '%s\n' 'q' ;;
    esac
}

echo "${BOLD}tui${RESET} $(ls "$TUI_DIR"/*.zy | wc -l) cases × ${#NAMES[@]} engines (${NAMES[*]})"

fail=0; stale=0; total=0
for file in "$TUI_DIR"/*.zy; do
    base="$(basename "$file" .zy)"
    total=$((total + 1))
    mapfile -t keys < <(keys_for "$base")

    declare -a outs=()
    for i in "${!NAMES[@]}"; do
        read -r -a argv <<< "${CMDS[$i]}"
        out="$(timeout 40 python3 "$TUI_DIR/ptydrive.py" "${argv[@]}" "$file" -- "${keys[@]}" 2>&1)"
        outs+=("$out")
    done

    # Equivalence classes, the same model zyq uses: one class means agreement,
    # and the shape of the classes names the outlier.
    same=1
    for i in "${!outs[@]}"; do
        [[ "${outs[$i]}" == "${outs[0]}" ]] || same=0
    done

    # A golden, when the case has one. Engine agreement cannot catch a fault
    # both engines share, and BUG-ZYB-006 was exactly that: `<<|` handed back
    # Ctrl+A as the letter `a` in the tree-walker AND in the VM, so this harness
    # called it agreement for as long as it existed. Same split as everywhere
    # else in zyquality — the goldens are the gate, the consensus is a finding.
    golden="${file%.zy}.expected"
    if [[ -f "$golden" ]]; then
        for i in "${!NAMES[@]}"; do
            if [[ "${outs[$i]}" != "$(cat "$golden")" ]]; then
                stale=$((stale + 1))
                echo ""
                echo "${RED}GOLDEN${RESET}  ${BOLD}$base${RESET} ${DIM}(${NAMES[$i]})  keys: ${keys[*]}${RESET}"
                diff <(printf '%s' "$(cat "$golden")") <(printf '%s' "${outs[$i]}") \
                    | head -12 | cat -v | sed 's/^/    /'
                break
            fi
        done
    fi

    if [[ $same -eq 1 ]]; then
        [[ $VERBOSE -eq 1 ]] && echo "  ${GREEN}AGREE${RESET}  $base"
    else
        fail=$((fail + 1))
        echo ""
        echo "${RED}DIVERGE${RESET} ${BOLD}$base${RESET}  ${DIM}keys: ${keys[*]}${RESET}"
        for i in "${!NAMES[@]}"; do
            printf '    %-8s %s\n' "${NAMES[$i]}" \
                "$(printf '%s' "${outs[$i]}" | head -c 90 | tr '\n' '|' | cat -v)"
        done
    fi
done

echo ""
echo "${BOLD}─────────────────────────────────────────────${RESET}"
# Stale goldens and divergences are counted apart, because they say different
# things. A divergence means one engine is wrong; a stale golden means the
# engines still agree and what they agree on has changed — which is the only
# way a shared fault such as BUG-ZYB-006 can ever show up here.
agree_line="${GREEN}$((total - fail)) agree${RESET}, "
if [[ $fail -eq 0 ]]; then
    agree_line="${GREEN}$total agree${RESET}, ${GREEN}0 diverge${RESET}"
else
    agree_line+="${RED}$fail diverge${RESET}"
fi
if [[ $stale -gt 0 ]]; then
    agree_line+=", ${RED}$stale stale${RESET}"
fi
echo "${BOLD}tui${RESET}        $total cases: $agree_line"
[[ $fail -eq 0 && $stale -eq 0 ]] || exit 1
