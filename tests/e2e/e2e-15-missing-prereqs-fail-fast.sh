#!/usr/bin/env bash
# tests/e2e/e2e-15-missing-prereqs-fail-fast.sh -- E2E-15.
#
# Requirement: Issue #100. install.sh must be purely user-local — no
# sudo invocations. When a distro-level prereq is missing, the script
# must exit with code 3 and print a copy-pasteable remediation command
# rather than either (a) calling sudo itself or (b) hanging on an
# invisible sudo password prompt.
#
# This is a function-level seam test: we source install.sh with
# BEGET_INSTALL_SOURCED=1 and invoke preflight_root_requirements
# directly, stubbing distro_pkg_installed to simulate a missing
# pinentry. A `sudo` stub on PATH exits 77 if ever invoked, so any
# accidental regression that reintroduces a sudo call will be caught.
#
# Pairs with E2E-13/14 (the Issue #98 seams).

set -uo pipefail
REPO="${REPO:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"
# shellcheck source=/dev/null
source "$REPO/tests/e2e/_lib.sh"

install_failing_sudo_stub() {
    # A sudo stub that exits non-zero on ANY invocation. install.sh must
    # never invoke it (the whole point of #100).
    local shim_dir="$1"
    mkdir -p "$shim_dir"
    cat >"$shim_dir/sudo" <<'EOF'
#!/usr/bin/env bash
echo "FAIL: sudo invoked from install.sh (args: $*)" >&2
exit 77
EOF
    chmod +x "$shim_dir/sudo"
}

run_test() {
    source_install "$REPO" || return 1

    # --- Case 1: missing prereq -> exit 3 + remediation, no sudo ---------
    local stub_dir
    stub_dir="$(mktemp -d)"
    install_failing_sudo_stub "$stub_dir"

    parse_flags || return 1

    # Mock the OS so the scan runs deterministically, then stub
    # distro_pkg_installed to simulate a missing pinentry-curses.
    OS_ID=ubuntu
    OS_MAJOR_VERSION=24
    distro_pkg_installed() { [[ "$1" != "pinentry-curses" ]]; }
    # Keep rocky_repo_enabled from matter on Ubuntu dispatch.
    rocky_repo_enabled() { return 1; }

    local rc=0 out
    out="$(
        PATH="$stub_dir:$PATH" preflight_root_requirements 2>&1
    )" || rc=$?

    if [[ $rc -ne 3 ]]; then
        _assert_fail "preflight_root_requirements: expected exit 3, got $rc. output: $out"
        rm -rf "$stub_dir"
        return 1
    fi

    assert_match "$out" "missing root-installed prerequisites" \
        "remediation header present" || {
        rm -rf "$stub_dir"
        return 1
    }
    assert_match "$out" "pinentry-curses" \
        "specific missing pkg named" || {
        rm -rf "$stub_dir"
        return 1
    }
    assert_match "$out" "install-prereqs.sh" \
        "points at scripts/install-prereqs.sh" || {
        rm -rf "$stub_dir"
        return 1
    }

    if [[ "$out" == *"FAIL: sudo invoked"* ]]; then
        _assert_fail "install.sh invoked sudo: $out"
        rm -rf "$stub_dir"
        return 1
    fi

    # --- Case 2: --skip-prereqs bypasses scan cleanly --------------------
    parse_flags --skip-prereqs || return 1
    rc=0
    out="$(
        PATH="$stub_dir:$PATH" preflight_root_requirements 2>&1
    )" || rc=$?
    if [[ $rc -ne 0 ]]; then
        _assert_fail "--skip-prereqs scan exited $rc (expected 0): $out"
        rm -rf "$stub_dir"
        return 1
    fi
    assert_match "$out" "skipping preflight_root_requirements" \
        "--skip-prereqs log line emitted" || {
        rm -rf "$stub_dir"
        return 1
    }

    # --- Case 3: install.sh + lib/platform.sh contain no live sudo calls -
    # The regression guard also lives in install.bats, but asserting it
    # here keeps the E2E wire contract explicit.
    if grep -nE '(^|[[:space:]])sudo[[:space:]]+[a-zA-Z]' \
        "$REPO/install.sh" "$REPO/lib/platform.sh" |
        grep -vE '^[^:]+:[[:digit:]]+:\s*#|printf .*sudo' >/dev/null; then
        _assert_fail "install.sh or lib/platform.sh still contains a live sudo call"
        rm -rf "$stub_dir"
        return 1
    fi

    rm -rf "$stub_dir"
}

start=$(date +%s)
failure=""
if ! run_test; then
    failure="assertions failed -- see stderr above"
fi

dur=$(($(date +%s) - start))
if [[ -z "$failure" ]]; then
    echo "E2E-15 PASS"
    emit_junit pass "$dur"
    exit 0
fi
echo "E2E-15 FAIL: $failure" >&2
emit_junit fail "$dur" "$failure"
exit 1
