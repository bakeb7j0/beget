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

    # Post-#100 the distro pkg list is computed by expected_distro_pkgs
    # (consumed by preflight_root_requirements). GNOME dispatch there
    # adds pinentry-gnome3; non-GNOME does not. Test both branches at
    # the function-seam level — the installer image is deliberately
    # non-GNOME, so we invoke expected_distro_pkgs directly rather than
    # relying on the container's XDG env.
    unset XDG_CURRENT_DESKTOP
    local base_list
    base_list="$(expected_distro_pkgs)" || return 1
    assert_match "$base_list" "pinentry-curses" "ubuntu base includes pinentry-curses" || return 1
    if [[ "$base_list" == *pinentry-gnome3* ]]; then
        _assert_fail "non-GNOME list should NOT contain pinentry-gnome3: $base_list"
        return 1
    fi

    # Force GNOME branch to confirm pinentry-gnome3 gets added.
    local gnome_list
    gnome_list="$(XDG_CURRENT_DESKTOP=GNOME expected_distro_pkgs)" || return 1
    assert_match "$gnome_list" "pinentry-gnome3" "GNOME branch adds pinentry-gnome3" || return 1

    # install_user_local in dry-run must still log chezmoi/direnv/rbw
    # intent (the user-local half of the split). preflight_root_requirements
    # itself is tested in E2E-15 and install.bats.
    local out
    out="$(install_user_local 2>&1)" || return 1
    assert_match "$out" "chezmoi" "dry-run mentions chezmoi" || return 1
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
