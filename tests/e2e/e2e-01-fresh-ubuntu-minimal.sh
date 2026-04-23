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

    # Post-#100 the prereq model is split: distro packages come from
    # scripts/install-prereqs.sh (baked into Dockerfile.ubuntu24 at build
    # time), and install.sh's preflight_root_requirements is a read-only
    # scan that exits 3 if anything is missing. On this image all
    # packages are present, so the scan must return 0.
    preflight_root_requirements || return 1

    # install_user_local in dry-run mode must emit markers for all three
    # upstream installers without actually invoking apt/cargo/curl. This
    # is the "chezmoi/rbw were never in the distro repos" invariant that
    # originally motivated R-01.
    #
    # chezmoi is baked into Dockerfile.ubuntu24 for speed, so install_chezmoi
    # hits the idempotency branch before DRY_RUN and logs "already installed"
    # instead of the dry-run marker. Accept either — both prove install_user_local
    # handled chezmoi. Same applies to direnv/rbw if a future image bakes them in.
    local out
    out="$(install_user_local 2>&1)" || return 1
    assert_match "$out" "chezmoi already installed|\[dry-run\] would install chezmoi" "chezmoi marker" || return 1
    assert_match "$out" "direnv already installed|\[dry-run\] would install direnv" "direnv marker" || return 1
    assert_match "$out" "rbw already installed|\[dry-run\] would cargo install rbw" "rbw marker" || return 1
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
