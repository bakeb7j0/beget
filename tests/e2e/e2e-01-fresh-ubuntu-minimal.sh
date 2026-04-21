#!/usr/bin/env bash
# tests/e2e/e2e-01-fresh-ubuntu-minimal.sh -- E2E-01.
#
# Requirement: R-01, R-06, R-30 -- `install.sh --role=minimal --skip-secrets`
# completes on Ubuntu 24.04.
#
# Strategy: source install.sh with BEGET_INSTALL_SOURCED=1 (so main()
# doesn't auto-run), call parse_flags + preflight with DRY_RUN=1 to
# avoid touching the host, assert the resolved role is `minimal` and
# that skip_secrets is set. The Dockerfile.ubuntu24 guarantees the OS
# identity; real package installs stay out of scope (the runner image
# already has chezmoi + curl + git).

set -uo pipefail
REPO="${REPO:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"
# shellcheck source=/dev/null
source "$REPO/tests/e2e/_lib.sh"

run_test() {
    source_install "$REPO" || return 1
    parse_flags --role=minimal --skip-secrets --dry-run || return 1

    assert_eq "$ROLE" "minimal" "role" || return 1
    assert_eq "$SKIP_SECRETS" "1" "skip_secrets" || return 1
    assert_eq "$DRY_RUN" "1" "dry_run" || return 1

    preflight || return 1
    assert_eq "$OS_ID" "ubuntu" "os_id" || return 1
    assert_eq "$OS_MAJOR_VERSION" "24" "os_major" || return 1

    # install_prereqs in dry-run mode must emit a pkg list but not
    # actually invoke apt.
    local out
    out="$(install_prereqs 2>&1)" || return 1
    assert_match "$out" "would pkg_install" "install_prereqs dry-run marker" || return 1
}

start=$(date +%s)
failure=""
if ! run_test; then
    failure="assertions failed -- see stderr above"
fi

dur=$(($(date +%s) - start))
if [[ -z "$failure" ]]; then
    echo "E2E-01 PASS"
    emit_junit pass "$dur"
    exit 0
fi
echo "E2E-01 FAIL: $failure" >&2
emit_junit fail "$dur" "$failure"
exit 1
