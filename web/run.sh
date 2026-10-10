#!/usr/bin/env bash
# web/run.sh — the web repository's own suites, inside the gate.
#
#   bash web/run.sh          # every suite that needs node and nothing else
#   bash web/run.sh -v       # each suite's own report, not only its last line
#
# `web/` keeps suites for the things that are not the language: the example
# pool, the Markdown twins, the licences, the published skill, the playground's
# translations and symbol cards, the stand-ins the browser has for a shell.
# `zyq consensus` cannot ask those questions, and until 2026-10-10 nothing in
# the gate did. `test_shell.mjs` was red for days — the browser refused the very
# command GO, Serpiente and Klingon Galaxy seed their generator with
# (ZYJS-059) — and `test_symbols.mjs` went red the day a row was added to
# REFERENCE.md § 21. Both were found by somebody running them by hand.
#
# Every `tests/test_*.mjs` in the web checkout is CLASSIFIED below: run here, or
# left out with its reason. A test file that is in neither list fails the suite,
# so a new one cannot stay outside the gate by not being mentioned.
#
# Exit status: 0 all pass, 1 one fails or is unclassified, 2 could not run.

set -u

HERE="$(cd "$(dirname "$0")" && pwd)"
WEB="${ZYQ_WEB_DIR:-$HERE/../../web}"
VERBOSE=0
[ "${1:-}" = "-v" ] && VERBOSE=1

if [ ! -d "$WEB/tests" ]; then
    echo "  the web/ checkout is not at $WEB (set ZYQ_WEB_DIR)" >&2
    exit 2
fi
command -v node >/dev/null 2>&1 || { echo "  node is not on PATH" >&2; exit 2; }

# Run with node alone.
RUN=(
    test_agents test_catalog test_check test_confusables test_filestore
    test_i18n_atlas test_i18n_playground test_licenses test_limits test_manual
    test_manual_v009 test_markdown test_shell test_symbols test_zyp
)
# Not run here, and why.
#   test_atlas_dom, test_playground_dom   drive a real browser
#   test_runner                           run below, over the example pool; over
#                                         the corpus it is `zyq consensus`
LEFT_OUT=(test_atlas_dom test_playground_dom test_runner)

fail=0

for f in "$WEB"/tests/test_*.mjs; do
    name="$(basename "$f" .mjs)"
    case " ${RUN[*]} ${LEFT_OUT[*]} " in
        *" $name "*) ;;
        *) printf '  ✗ %-22s is in web/tests/ and in neither list of web/run.sh\n' "$name"; fail=1 ;;
    esac
done

run_one() {  # label, then the command
    local label="$1"; shift
    local out rc
    out="$(cd "$WEB" && "$@" 2>&1)"; rc=$?
    if [ $rc -eq 0 ]; then
        # What the suite said about itself: its verdict line when it has one
        # with a count in it, its last line otherwise.
        local plain said
        plain="$(printf '%s\n' "$out" | sed 's/\x1b\[[0-9;]*m//g' | awk 'NF')"
        said="$(printf '%s\n' "$plain" | grep -E '^consensus ' | tail -1)"
        [ -z "$said" ] && said="$(printf '%s\n' "$plain" | tail -1)"
        printf '  ✓ %-22s %s\n' "$label" "$said"
        [ $VERBOSE -eq 1 ] && printf '%s\n' "$out" | sed 's/^/      /'
    else
        printf '  ✗ %-22s exit %d\n' "$label" "$rc"
        printf '%s\n' "$out" | tail -20 | sed 's/^/      /'
        fail=1
    fi
}

for name in "${RUN[@]}"; do
    if [ ! -f "$WEB/tests/$name.mjs" ]; then
        printf '  ✗ %-22s is listed in web/run.sh and not in web/tests/\n' "$name"; fail=1
        continue
    fi
    run_one "$name" node "tests/$name.mjs"
done

# The example pool: every playground example, through the CLI and the browser
# engine. Four of them had been broken since v0.0.6 while they lived inside a JS
# module, where no tool could reach them.
run_one "examples" node tests/test_runner.mjs --dir examples

exit $fail
