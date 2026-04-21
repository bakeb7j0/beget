#!/usr/bin/env bash
# tests/e2e/e2e-02-fresh-ubuntu-workstation.sh -- E2E-02.
#
# Requirement: R-30, R-33 -- `install.sh --role=workstation --skip-secrets`
# completes on Ubuntu 24.04.

set -uo pipefail
REPO="${REPO:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"
# shellcheck source=/dev/null
source "$REPO/tests/e2e/_lib.sh"

run_test() {
    source_install "$REPO" || return 1
    parse_flags --role=workstation --skip-secrets --dry-run || return 1

    assert_eq "$ROLE" "workstation" || return 1
    assert_eq "$SKIP_SECRETS" "1" || return 1

    preflight || return 1
    assert_eq "$OS_ID" "ubuntu" || return 1

    # Workstation role should include pinentry-gnome3 if GNOME, else
    # base list only. XDG_CURRENT_DESKTOP is unset in the container so
    # is_gnome returns 1 and we should NOT see pinentry-gnome3.
    unset XDG_CURRENT_DESKTOP
    local out
    out="$(install_prereqs 2>&1)" || return 1
    assert_match "$out" "chezmoi" "prereqs mention chezmoi" || return 1

    # Force GNOME branch to confirm pinentry-gnome3 gets added.
    # shellcheck disable=SC2034
    export XDG_CURRENT_DESKTOP="GNOME"
    local out2
    out2="$(install_prereqs 2>&1)" || return 1
    assert_match "$out2" "pinentry-gnome3" "GNOME branch adds pinentry-gnome3" || return 1
}

start=$(date +%s)
failure=""
if ! run_test; then
    failure="assertions failed -- see stderr above"
fi

dur=$(($(date +%s) - start))
if [[ -z "$failure" ]]; then
    echo "E2E-02 PASS"
    emit_junit pass "$dur"
    exit 0
fi
echo "E2E-02 FAIL: $failure" >&2
emit_junit fail "$dur" "$failure"
exit 1
