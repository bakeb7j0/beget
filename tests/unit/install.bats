#!/usr/bin/env bats
# tests/unit/install.bats — unit tests for install.sh flag parsing + pre-flight

setup() {
    REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
    INSTALL_SH="$REPO_ROOT/install.sh"
}

@test "install.sh: --help prints usage and lists all 5 flags" {
    run bash "$INSTALL_SH" --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"--dry-run"* ]]
    [[ "$output" == *"--role="* ]]
    [[ "$output" == *"--skip-secrets"* ]]
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

@test "install.sh: parse_flags sets DRY_RUN/ROLE/SKIP_SECRETS/ALLOW_ROOT" {
    source_install
    parse_flags --dry-run --role=minimal --skip-secrets --allow-root
    [ "$DRY_RUN" -eq 1 ]
    [ "$ROLE" = "minimal" ]
    [ "$SKIP_SECRETS" -eq 1 ]
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
