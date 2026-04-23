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

    # Post-#100 the distro pkg list for Rocky is computed by
    # expected_distro_pkgs — pinentry (no -curses suffix),
    # pkgconf-pkg-config (the RPM that provides /usr/bin/pkg-config;
    # `pkg-config` is only a Provides, not a real package name, and our
    # rpm -q scan needs the real name), openssl-devel, gcc. Ubuntu-only
    # packages must not appear.
    local pkgs
    pkgs="$(expected_distro_pkgs)" || return 1
    assert_match "$pkgs" "openssl-devel" "rocky list has openssl-devel" || return 1
    assert_match "$pkgs" "gcc" "rocky list has gcc" || return 1
    assert_match "$pkgs" "pkgconf-pkg-config" "rocky list uses real RPM name for pkg-config" || return 1
    if [[ "$pkgs" == *libssl-dev* || "$pkgs" == *build-essential* ]]; then
        _assert_fail "rocky list leaked ubuntu-only pkgs: $pkgs"
        return 1
    fi

    # preflight_root_requirements is a read-only scan; in the Rocky E2E
    # image scripts/install-prereqs.sh has already baked in the expected
    # packages + EPEL + CRB, so the scan must exit 0 cleanly.
    preflight_root_requirements || return 1

    # install_user_local in dry-run must still log the upstream installer
    # intent. These are the same across distros (chezmoi/direnv/rbw all
    # come from upstream installers, not dnf).
    local out
    out="$(install_user_local 2>&1)" || return 1
    assert_match "$out" "\[dry-run\] would cargo install rbw" "rbw dry-run marker" || return 1
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
