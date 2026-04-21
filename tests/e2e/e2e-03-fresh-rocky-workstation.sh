#!/usr/bin/env bash
# tests/e2e/e2e-03-fresh-rocky-workstation.sh -- E2E-03.
#
# Requirement: R-02 -- `install.sh --role=workstation --skip-secrets`
# completes on Rocky 9.

set -uo pipefail
REPO="${REPO:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"
# shellcheck source=/dev/null
source "$REPO/tests/e2e/_lib.sh"

run_test() {
    source_install "$REPO" || return 1
    parse_flags --role=workstation --skip-secrets --dry-run || return 1

    preflight || return 1
    assert_eq "$OS_ID" "rocky" "os_id (expect rocky on Dockerfile.rocky9)" || return 1
    assert_eq "$OS_MAJOR_VERSION" "9" "os_major" || return 1

    local out
    out="$(install_prereqs 2>&1)" || return 1
    # Dry-run marker should appear -- the pkg list itself may vary.
    assert_match "$out" "pkg_install" "install_prereqs dispatched" || return 1
}

start=$(date +%s)
failure=""
if ! run_test; then
    failure="assertions failed -- see stderr above"
fi

dur=$(($(date +%s) - start))
if [[ -z "$failure" ]]; then
    echo "E2E-03 PASS"
    emit_junit pass "$dur"
    exit 0
fi
echo "E2E-03 FAIL: $failure" >&2
emit_junit fail "$dur" "$failure"
exit 1
