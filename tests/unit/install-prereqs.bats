#!/usr/bin/env bats
# tests/unit/install-prereqs.bats — unit tests for scripts/install-prereqs.sh
#
# Exercises the distro-dispatch logic via DRY_RUN + a synthesized
# /etc/os-release. No real package-manager calls are made.

setup() {
    REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
    PREREQS_SH="$REPO_ROOT/scripts/install-prereqs.sh"
    # shellcheck source=/dev/null
    source "$REPO_ROOT/tests/helpers/mocks.sh"
}

teardown() {
    reset_os_env
}

@test "install-prereqs.sh: --help prints usage and exits 0" {
    run bash "$PREREQS_SH" --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"Usage:"* ]]
    [[ "$output" == *"--dry-run"* ]]
}

@test "install-prereqs.sh: unknown flag aborts non-zero" {
    run bash "$PREREQS_SH" --bogus
    [ "$status" -ne 0 ]
    [[ "$output" == *"unknown argument"* ]]
}

@test "install-prereqs.sh: reports clear error and exits 2 when not run as root" {
    # Must not pass --dry-run here — --dry-run bypasses the root check.
    # We invoke as the unprivileged bats runner; EUID != 0.
    run bash "$PREREQS_SH"
    [ "$status" -eq 2 ]
    [[ "$output" == *"must be run as root"* ]]
    [[ "$output" == *"sudo"* ]]
}

@test "install-prereqs.sh: ubuntu --dry-run lists expected pkg set (pinentry-curses, libssl-dev, build-essential)" {
    make_os_release "ubuntu" "24.04"
    # Disable GNOME detection so the test is deterministic regardless of
    # the runner's XDG_CURRENT_DESKTOP.
    XDG_CURRENT_DESKTOP="" OS_RELEASE_FILE="$OS_RELEASE_FILE" run bash "$PREREQS_SH" --dry-run
    [ "$status" -eq 0 ]
    [[ "$output" == *"apt-get update"* ]]
    [[ "$output" == *"pinentry-curses"* ]]
    [[ "$output" == *"git"* ]]
    [[ "$output" == *"curl"* ]]
    [[ "$output" == *"pkg-config"* ]]
    [[ "$output" == *"libssl-dev"* ]]
    [[ "$output" == *"build-essential"* ]]
    # Rocky-only packages must not appear on Ubuntu.
    [[ "$output" != *"openssl-devel"* ]]
}

@test "install-prereqs.sh: ubuntu GNOME --dry-run additionally includes pinentry-gnome3" {
    make_os_release "ubuntu" "24.04"
    XDG_CURRENT_DESKTOP="GNOME" OS_RELEASE_FILE="$OS_RELEASE_FILE" run bash "$PREREQS_SH" --dry-run
    [ "$status" -eq 0 ]
    [[ "$output" == *"pinentry-gnome3"* ]]
}

@test "install-prereqs.sh: rocky --dry-run enables EPEL + CRB then installs (openssl-devel, gcc)" {
    make_os_release "rocky" "9.3"
    XDG_CURRENT_DESKTOP="" OS_RELEASE_FILE="$OS_RELEASE_FILE" run bash "$PREREQS_SH" --dry-run
    [ "$status" -eq 0 ]
    # EPEL enablement comes first.
    [[ "$output" == *"epel-release"* ]]
    [[ "$output" == *"config-manager --set-enabled crb"* ]]
    # Then dnf install of the full Rocky pkg set.
    [[ "$output" == *"dnf"* ]]
    [[ "$output" == *"pinentry"* ]]
    [[ "$output" == *"pkg-config"* ]]
    [[ "$output" == *"openssl-devel"* ]]
    [[ "$output" == *"gcc"* ]]
    # Ubuntu-only packages must not appear on Rocky.
    [[ "$output" != *"libssl-dev"* ]]
    [[ "$output" != *"build-essential"* ]]
}

@test "install-prereqs.sh: --dry-run bypasses root check and marks every side-effecting cmd" {
    # Exercised as non-root (bats runner is EUID != 0). If --dry-run did
    # NOT bypass require_root, the script would exit 2 instead of 0.
    # If any side-effecting command leaked through --dry-run, its stdout
    # would appear WITHOUT the `[dry-run]` prefix produced by run_cmd.
    make_os_release "ubuntu" "24.04"
    XDG_CURRENT_DESKTOP="" OS_RELEASE_FILE="$OS_RELEASE_FILE" \
        run bash "$PREREQS_SH" --dry-run
    [ "$status" -eq 0 ]
    [[ "$output" == *"[dry-run] apt-get update"* ]]
    [[ "$output" == *"[dry-run] apt-get install"* ]]
}

@test "install-prereqs.sh: unsupported OS aborts with clear message" {
    make_os_release "arch" "rolling"
    OS_RELEASE_FILE="$OS_RELEASE_FILE" run bash "$PREREQS_SH" --dry-run
    [ "$status" -ne 0 ]
    [[ "$output" == *"unsupported OS"* ]]
    [[ "$output" == *"arch"* ]]
}

@test "install-prereqs.sh: passes shellcheck" {
    if ! command -v shellcheck >/dev/null 2>&1; then
        skip "shellcheck not installed"
    fi
    run shellcheck "$PREREQS_SH"
    [ "$status" -eq 0 ]
}
