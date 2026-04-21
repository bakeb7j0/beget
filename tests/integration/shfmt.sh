#!/usr/bin/env bash
# tests/integration/shfmt.sh -- IT-02.
#
# Run shfmt --diff over every *.sh in scope (same target list as the
# integration shellcheck script). Any diff output is a failure --
# formatting drift breaks the build.

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$REPO_ROOT" || {
    echo "cannot cd to $REPO_ROOT" >&2
    exit 2
}

if ! command -v shfmt >/dev/null 2>&1; then
    echo "shfmt not installed" >&2
    exit 2
fi

shopt -s nullglob globstar

targets=()
[[ -f install.sh ]] && targets+=(install.sh)
targets+=(lib/*.sh)
targets+=(scripts/**/*.sh)
targets+=(tests/integration/*.sh)
targets+=(tests/helpers/*.sh)

for f in run_onchange_*; do
    [[ -f "$f" ]] || continue
    case "$f" in
        *.tmpl) ;; # chezmoi-rendered; shfmt can't parse the template.
        *) targets+=("$f") ;;
    esac
done

if [[ ${#targets[@]} -eq 0 ]]; then
    echo "shfmt: no files to check"
    exit 0
fi

fail=0
for f in "${targets[@]}"; do
    [[ -f "$f" ]] || continue
    # shfmt prints the diff to stdout. Capture; fail if non-empty.
    if ! diff_out="$(shfmt --diff -i 4 -ci "$f" 2>&1)"; then
        printf 'FAIL (shfmt error): %s\n%s\n' "$f" "$diff_out" >&2
        fail=1
        continue
    fi
    if [[ -n "$diff_out" ]]; then
        printf 'FAIL (format drift): %s\n%s\n' "$f" "$diff_out" >&2
        fail=1
    fi
done
exit "$fail"
