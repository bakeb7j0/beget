#!/usr/bin/env bash
# tests/integration/shellcheck.sh — IT-01.
#
# Run shellcheck across every *.sh under the repo (excluding the bats
# submodule and vendored trees). Aggregates failures: one offender per
# file is reported; the script exits non-zero if any file fails. Prints
# file:line so failure output is copy-pastable.

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$REPO_ROOT" || {
    echo "cannot cd to $REPO_ROOT" >&2
    exit 2
}

if ! command -v shellcheck >/dev/null 2>&1; then
    echo "shellcheck not installed" >&2
    exit 2
fi

# Build the target list. Aligns with the existing `make lint` scope plus
# CI and integration test scripts added by Story #27. We deliberately
# SKIP dot_bashrc.d/*.sh (sourced fragments without shebangs) and *.tmpl
# files (chezmoi-rendered, not raw bash).
shopt -s nullglob globstar

targets=()
[[ -f install.sh ]] && targets+=(install.sh)
targets+=(lib/*.sh)
targets+=(scripts/**/*.sh)
targets+=(tests/integration/*.sh)
targets+=(tests/helpers/*.sh)

# run_onchange_* files that are plain .sh (no .tmpl suffix) are pure bash.
for f in run_onchange_*; do
    [[ -f "$f" ]] || continue
    case "$f" in
        *.tmpl) ;; # chezmoi will render; skip shellcheck.
        *) targets+=("$f") ;;
    esac
done

if [[ ${#targets[@]} -eq 0 ]]; then
    echo "shellcheck: no files to check"
    exit 0
fi

echo "shellcheck: $(printf '%s ' "${targets[@]}")"

fail=0
for f in "${targets[@]}"; do
    [[ -f "$f" ]] || continue
    if ! shellcheck "$f"; then
        printf 'FAIL: %s\n' "$f" >&2
        fail=1
    fi
done
exit "$fail"
