#!/usr/bin/env bash
# tests/e2e/e2e-08-root-refusal.sh -- E2E-08.
#
# Requirement: R-03 -- install.sh refuses to run as root without
# --allow-root. We can run the test as a non-root user by stubbing
# `current_euid` to return 0, since source_install exposes the
# function for overriding.

set -uo pipefail
REPO="${REPO:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"
# shellcheck source=/dev/null
source "$REPO/tests/e2e/_lib.sh"

run_test() {
    source_install "$REPO" || return 1
    parse_flags --role=minimal --skip-secrets || return 1

    # Override current_euid to simulate uid 0 (invoked indirectly by
    # preflight -- shellcheck can't see the dynamic dispatch).
    # shellcheck disable=SC2317
    current_euid() { echo 0; }

    # preflight must abort with a non-zero exit and an error mentioning
    # root / --allow-root.
    local out
    if out="$(preflight 2>&1)"; then
        _assert_fail "preflight succeeded as fake-root without --allow-root"
        return 1
    fi
    assert_match "$out" "(root|allow-root|R-03)" "preflight rejects root" || return 1

    # With --allow-root the same euid-0 scenario must NOT trigger the
    # root-refusal branch. ALLOW_ROOT is read by preflight() in
    # install.sh.
    # shellcheck disable=SC2034
    ALLOW_ROOT=1
    local out2 rc=0
    out2="$(preflight 2>&1)" || rc=$?
    if [[ $rc -ne 0 ]]; then
        _assert_fail "--allow-root: preflight still exited non-zero ($rc): $out2"
        return 1
    fi
    if [[ "$out2" == *"refusing to run as root"* ]]; then
        _assert_fail "--allow-root did not bypass R-03 refusal"
        return 1
    fi
}

start=$(date +%s)
failure=""
if ! run_test; then
    failure="assertions failed -- see stderr above"
fi

dur=$(($(date +%s) - start))
if [[ -z "$failure" ]]; then
    echo "E2E-08 PASS"
    emit_junit pass "$dur"
    exit 0
fi
echo "E2E-08 FAIL: $failure" >&2
emit_junit fail "$dur" "$failure"
exit 1
