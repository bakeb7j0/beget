#!/usr/bin/env bash
# tests/e2e/e2e-05-rerun-idempotency.sh -- E2E-05.
#
# Requirement: R-07, R-08 -- re-running install.sh on an already-
# bootstrapped container is safe. We simulate this at the function
# level: parse_flags and preflight twice with the same dry-run inputs
# must leave state consistent.

set -uo pipefail
REPO="${REPO:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"
# shellcheck source=/dev/null
source "$REPO/tests/e2e/_lib.sh"

run_test() {
    source_install "$REPO" || return 1

    # First pass.
    parse_flags --role=minimal --skip-secrets --dry-run || return 1
    preflight || return 1
    local role1="$ROLE"
    local skip1="$SKIP_SECRETS"
    local os1="$OS_ID"

    # Second pass with the same inputs.
    parse_flags --role=minimal --skip-secrets --dry-run || return 1
    preflight || return 1
    assert_eq "$ROLE" "$role1" "role stable across re-runs" || return 1
    assert_eq "$SKIP_SECRETS" "$skip1" "skip_secrets stable" || return 1
    assert_eq "$OS_ID" "$os1" "os_id stable" || return 1

    # Post-#100 the equivalent idempotency contract is on the two new
    # function seams: preflight_root_requirements (read-only scan —
    # identical rc and log every time) and install_user_local in
    # dry-run (logs intent only, must be stable across re-runs).
    preflight_root_requirements || return 1
    preflight_root_requirements || return 1

    local out1 out2
    out1="$(install_user_local 2>&1)" || return 1
    out2="$(install_user_local 2>&1)" || return 1
    assert_eq "$out1" "$out2" "install_user_local output stable across re-runs" || return 1
}

start=$(date +%s)
failure=""
if ! run_test; then
    failure="assertions failed -- see stderr above"
fi

dur=$(($(date +%s) - start))
if [[ -z "$failure" ]]; then
    echo "E2E-05 PASS"
    emit_junit pass "$dur"
    exit 0
fi
echo "E2E-05 FAIL: $failure" >&2
emit_junit fail "$dur" "$failure"
exit 1
