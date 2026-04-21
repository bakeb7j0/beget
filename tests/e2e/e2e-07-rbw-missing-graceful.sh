#!/usr/bin/env bash
# tests/e2e/e2e-07-rbw-missing-graceful.sh -- E2E-07.
#
# Requirement: R-23 -- when rbw reports a missing item, chezmoi apply
# / execute-template fails with a clear error rather than silently
# emitting garbage.

set -uo pipefail
REPO="${REPO:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"
# shellcheck source=/dev/null
source "$REPO/tests/e2e/_lib.sh"

run_test() (
    with_mock_rbw missing
    cd "$REPO" || return 1

    local ssh_tpl="$REPO/private_dot_ssh/private_id_ed25519.tmpl"
    if [[ ! -f "$ssh_tpl" ]]; then
        _assert_fail "SSH template missing: $ssh_tpl"
        return 1
    fi

    # chezmoi execute-template should fail with non-zero and an
    # error mentioning rbw (or the item name).
    local out
    if out="$(chezmoi execute-template --source "$REPO" <"$ssh_tpl" 2>&1)"; then
        _assert_fail "chezmoi succeeded despite rbw missing: $out"
        return 1
    fi
    assert_match "$out" "(rbw|no item|ssh-id-)" "error message references rbw" || return 1
)

start=$(date +%s)
failure=""
if ! run_test; then
    failure="assertions failed -- see stderr above"
fi

dur=$(($(date +%s) - start))
if [[ -z "$failure" ]]; then
    echo "E2E-07 PASS"
    emit_junit pass "$dur"
    exit 0
fi
echo "E2E-07 FAIL: $failure" >&2
emit_junit fail "$dur" "$failure"
exit 1
