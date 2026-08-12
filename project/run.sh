#!/usr/bin/env bash
# project/run.sh — the real programs written in Zymbol, through every engine.
#
#   bash project/run.sh              # every app
#   bash project/run.sh --only go    # one of them
#   bash project/run.sh -v           # name the suites that pass too
#   bash project/run.sh --engines zytw,zyvm
#
# Two questions per app, and they are not the same question:
#
#   goldens    does this suite still print what it printed?  A regression in the
#              application, or in the engine under it.  **This is the gate**:
#              the point of these suites is to validate what already works.
#
#   consensus  do the engines agree about it?  A divergence, which is a finding
#              rather than a regression — an engine being behind does not mean
#              the application broke.  Reported, not gated.
#
# Correctness used to be `grep -q FAIL` over the suite's output, in a runner per
# project. A suite that crashes half way through prints no FAIL and passes; that
# was verified, not supposed. A golden does not match a truncated run.
#
# Exit status: 0 every golden holds, 1 one does not, 2 could not run.
#
# An app whose checkout is absent, or whose goldens have never been recorded, is
# reported and not counted either way. The suites live in the applications'
# repositories; this one owns the registry and the verdict, not the files.

set -uo pipefail

PROJ_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ZYQ_HOME="$(cd "$PROJ_DIR/.." && pwd)"
ZYQ="$ZYQ_HOME/zyq"
APPS="$PROJ_DIR/apps.toml"

RED=$'\033[0;31m'; GREEN=$'\033[0;32m'; YELLOW=$'\033[1;33m'
CYAN=$'\033[0;36m'; DIM=$'\033[2m'; BOLD=$'\033[1m'; RESET=$'\033[0m'

[[ -x "$ZYQ" ]] || { echo "project/run.sh: build zyq first: make -C '$ZYQ_HOME'" >&2; exit 2; }
[[ -f "$APPS" ]] || { echo "project/run.sh: no registry at $APPS" >&2; exit 2; }

ONLY=""
VERBOSE=0
TIMEOUT=120

# These are command-line applications: a go engine, two TUI games, a code
# auditor. The browser engine has no terminal, no filesystem and no shell, so
# comparing it against them is not a question anybody is asking -- it diverges
# on all of them and says nothing. Override with --engines when it is.
ENGINES="${ZY_APP_ENGINES:-zytw,zyvm,zyml}"
while [[ $# -gt 0 ]]; do
    case "$1" in
        --only)    ONLY="$2"; shift 2 ;;
        --engines) ENGINES="$2"; shift 2 ;;
        --timeout) TIMEOUT="$2"; shift 2 ;;
        -v|--verbose) VERBOSE=1; shift ;;
        -h|--help) sed -n '2,24p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        *) echo "project/run.sh: unknown option: $1" >&2; exit 2 ;;
    esac
done

# ── Read the registry ─────────────────────────────────────────────────────────
# Only the two keys this needs, from `[[app]]` tables. zyq has a real TOML
# reader; this is the one place that cannot use it, so it stays deliberately
# small and refuses anything it does not recognise rather than skipping it.
read_apps() {
    awk '
        /^[[:space:]]*#/    { next }
        /^\[\[app\]\][[:space:]]*$/ { if (id != "") print id "\t" dir "\t" desc; id=dir=desc=""; next }
        /^[[:space:]]*id[[:space:]]*=/   { sub(/^[^=]*=[[:space:]]*/, ""); gsub(/"/, ""); id=$0;   next }
        /^[[:space:]]*dir[[:space:]]*=/  { sub(/^[^=]*=[[:space:]]*/, ""); gsub(/"/, ""); dir=$0;  next }
        /^[[:space:]]*desc[[:space:]]*=/ { sub(/^[^=]*=[[:space:]]*/, ""); gsub(/"/, ""); desc=$0; next }
        END { if (id != "") print id "\t" dir "\t" desc }
    ' "$APPS"
}

wanted() { [[ -z "$ONLY" ]] || [[ ",$ONLY," == *",$1,"* ]]; }

echo "${BOLD}project${RESET} the real programs written in Zymbol"

fail=0; ran=0; absent=0; unset_apps=0
while IFS=$'\t' read -r id dir desc; do
    wanted "$id" || continue
    abs="$ZYQ_HOME/$dir"

    if [[ ! -d "$abs" ]]; then
        absent=$((absent + 1))
        printf '\n%s %-10s %s\n' "${YELLOW}ABSENT${RESET}" "$id" \
               "${DIM}$dir — this workspace does not have that checkout${RESET}"
        continue
    fi

    ran=$((ran + 1))
    printf '\n%s %s %s\n' "${CYAN}──${RESET}" "${BOLD}$id${RESET}" "${DIM}$desc${RESET}"

    # The gate: has anything stopped printing what it printed?
    #
    # Exit 1 and exit 2 are different answers and must not be merged. A stale
    # golden is a regression; no goldens at all means this app has never been
    # recorded — its suites live in another repository, and a checkout that has
    # not had them recorded yet is unconfigured, not broken.
    out="$("$ZYQ" --root "$ZYQ_HOME" expect --corpus "$abs" \
            --timeout "$TIMEOUT" --no-colour $([[ $VERBOSE -eq 1 ]] && echo -v) 2>&1)"
    rc=$?
    case $rc in
        0)  echo "  ${GREEN}goldens${RESET}   $(grep -a 'goldens via' <<<"$out" | tail -1 | sed 's/^expect *//')" ;;
        1)  fail=$((fail + 1))
            echo "  ${RED}goldens${RESET}   $(grep -a 'goldens via' <<<"$out" | tail -1 | sed 's/^expect *//')"
            grep -a -A3 '^STALE' <<<"$out" | sed 's/^/    /' ;;
        *)  unset_apps=$((unset_apps + 1))
            echo "  ${YELLOW}goldens${RESET}   ${DIM}none recorded — nothing to compare against${RESET}"
            echo "            ${DIM}record them:  ./zyq expect --regen --new --engines zytw --corpus $dir${RESET}" ;;
    esac

    # The finding: do the engines agree?  Never fails this runner.
    out="$("$ZYQ" --root "$ZYQ_HOME" consensus --corpus "$abs" --engines "$ENGINES" \
            --timeout "$TIMEOUT" --no-colour 2>&1)"
    line="$(grep -a 'files:' <<<"$out" | tail -1 | sed 's/^consensus *//')"
    if grep -aq 'DIVERGE' <<<"$out"; then
        echo "  ${YELLOW}engines${RESET}   $line"
        grep -a '^DIVERGE' <<<"$out" | sed 's/^DIVERGE /    diverges: /'
    else
        echo "  ${GREEN}engines${RESET}   $line"
    fi
done < <(read_apps)

echo ""
echo "${BOLD}─────────────────────────────────────────────${RESET}"
printf '%s    %d app(s)' "${BOLD}project${RESET}" "$ran"
if [[ $fail -eq 0 ]]; then
    printf ': %s\n' "${GREEN}every golden holds${RESET}"
else
    printf ': %s\n' "${RED}${fail} with a stale golden${RESET}"
fi
[[ $absent -eq 0 ]] || echo "${DIM}${absent} checkout(s) not present and therefore not tested${RESET}"
[[ $unset_apps -eq 0 ]] || echo "${YELLOW}${unset_apps} app(s) have no goldens recorded — see the command above${RESET}"

[[ $fail -eq 0 ]] || exit 1
