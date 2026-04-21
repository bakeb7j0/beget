#!/usr/bin/env bats
# tests/unit/install.bats — unit tests for install.sh flag parsing + pre-flight

setup() {
    REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
    INSTALL_SH="$REPO_ROOT/install.sh"
}

@test "install.sh: --help prints usage and lists all flags" {
    run bash "$INSTALL_SH" --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"--dry-run"* ]]
    [[ "$output" == *"--role="* ]]
    [[ "$output" == *"--skip-secrets"* ]]
    [[ "$output" == *"--skip-apply"* ]]
    [[ "$output" == *"--allow-root"* ]]
    [[ "$output" == *"--help"* ]]
}

@test "install.sh: -h is an alias for --help" {
    run bash "$INSTALL_SH" -h
    [ "$status" -eq 0 ]
    [[ "$output" == *"Usage:"* ]]
}

@test "install.sh: unknown flag aborts with error" {
    run bash "$INSTALL_SH" --bogus-flag
    [ "$status" -ne 0 ]
    [[ "$output" == *"unknown flag"* ]]
}

@test "install.sh: --role= (empty) rejected" {
    run bash "$INSTALL_SH" --role=
    [ "$status" -ne 0 ]
    [[ "$output" == *"--role"* ]]
}

# Source install.sh without running main, then exercise parse_flags +
# preflight directly with a mocked id() so we can assert the R-03 root
# rejection branch.
source_install() {
    export BEGET_INSTALL_SOURCED=1
    # shellcheck source=/dev/null
    source "$INSTALL_SH"
}

@test "install.sh: parse_flags sets DRY_RUN/ROLE/SKIP_SECRETS/SKIP_APPLY/ALLOW_ROOT" {
    source_install
    parse_flags --dry-run --role=minimal --skip-secrets --skip-apply --allow-root
    [ "$DRY_RUN" -eq 1 ]
    [ "$ROLE" = "minimal" ]
    [ "$SKIP_SECRETS" -eq 1 ]
    [ "$SKIP_APPLY" -eq 1 ]
    [ "$ALLOW_ROOT" -eq 1 ]
}

@test "install.sh: preflight rejects root without --allow-root (R-03)" {
    source_install
    parse_flags --skip-secrets  # no --allow-root
    # Override the current_euid seam to pretend we're root.
    current_euid() { printf '0\n'; }
    run preflight
    [ "$status" -ne 0 ]
    [[ "$output" == *"refusing to run as root"* ]]
    [[ "$output" == *"R-03"* ]]
}

@test "install.sh: preflight allows root with --allow-root (R-03 override)" {
    source_install
    parse_flags --skip-secrets --allow-root
    current_euid() { printf '0\n'; }
    run preflight
    # preflight may still fail on network / OS checks in a CI box — we only
    # assert that the R-03 root-reject message is NOT present.
    [[ "$output" != *"refusing to run as root"* ]]
}

@test "install.sh: passes shellcheck" {
    if ! command -v shellcheck >/dev/null 2>&1; then
        skip "shellcheck not installed"
    fi
    run shellcheck "$INSTALL_SH"
    [ "$status" -eq 0 ]
}

@test "install.sh: install_prereqs dry-run emits distro and upstream markers" {
    source_install
    parse_flags --dry-run --role=minimal --skip-secrets
    # Source the library so install_prereqs can resolve install_chezmoi /
    # install_rbw / is_gnome. The OS dispatch never executes because
    # DRY_RUN=1, but OS_ID is still needed for install_rbw's guard.
    # shellcheck source=/dev/null
    source "$REPO_ROOT/lib/platform.sh"
    source "$REPO_ROOT/tests/helpers/mocks.sh"
    make_os_release "ubuntu" "24.04"
    source_os_release

    run install_prereqs
    [ "$status" -eq 0 ]
    [[ "$output" == *"would pkg_install"* ]]
    [[ "$output" == *"upstream prereqs"* ]]
    [[ "$output" == *"chezmoi"* ]]
    [[ "$output" == *"rbw"* ]]
}

@test "install.sh: install_prereqs dry-run never invokes real curl or cargo" {
    source_install
    parse_flags --dry-run --role=minimal --skip-secrets
    # shellcheck source=/dev/null
    source "$REPO_ROOT/lib/platform.sh"
    source "$REPO_ROOT/tests/helpers/mocks.sh"
    make_os_release "ubuntu" "24.04"
    source_os_release

    # Stub curl/cargo/sh/pkg_install to fail loudly if the dry-run branch
    # accidentally invokes them. command -v chezmoi / rbw will already
    # return true in the sourced test environment, so we also wipe those
    # via a restricted PATH to force the [dry-run] branch.
    curl() { printf 'FAIL: curl called\n' >&2; return 99; }
    cargo() { printf 'FAIL: cargo called\n' >&2; return 99; }
    pkg_install() { printf 'FAIL: pkg_install called\n' >&2; return 99; }
    export -f curl cargo pkg_install

    # Sandbox PATH so chezmoi / rbw are NOT found — forces the install
    # branch inside install_chezmoi / install_rbw, which should still
    # short-circuit on DRY_RUN=1.
    PATH="/nonexistent" run install_prereqs
    [ "$status" -eq 0 ]
    [[ "$output" != *"FAIL: curl called"* ]]
    [[ "$output" != *"FAIL: cargo called"* ]]
    [[ "$output" != *"FAIL: pkg_install called"* ]]
}
