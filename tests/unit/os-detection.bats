#!/usr/bin/env bats
# tests/unit/os-detection.bats — OS-release edge-case coverage for
# lib/platform.sh::source_os_release and die_if_unsupported_os.
#
# Focus: cases tests/unit/platform.bats doesn't cover — quoting variants,
# unusual version strings, codename-only releases, and boundary conditions
# on die_if_unsupported_os.

setup() {
    REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
    # shellcheck source=/dev/null
    source "$REPO_ROOT/tests/helpers/mocks.sh"
    reset_os_env
    # shellcheck source=/dev/null
    source "$REPO_ROOT/lib/platform.sh"
}

teardown() {
    reset_os_env
}

# ---- source_os_release quoting and format variants -------------------------

@test "source_os_release: unquoted ID, quoted VERSION_ID" {
    cat >"$BATS_TEST_TMPDIR/os-release" <<'EOF'
NAME="Ubuntu"
ID=ubuntu
VERSION_ID="24.04"
EOF
    export OS_RELEASE_FILE="$BATS_TEST_TMPDIR/os-release"
    source_os_release
    [ "$OS_ID" = "ubuntu" ]
    [ "$OS_MAJOR_VERSION" = "24" ]
}

@test "source_os_release: quoted ID, unquoted VERSION_ID" {
    cat >"$BATS_TEST_TMPDIR/os-release" <<'EOF'
NAME="Rocky Linux"
ID="rocky"
VERSION_ID=9
EOF
    export OS_RELEASE_FILE="$BATS_TEST_TMPDIR/os-release"
    source_os_release
    [ "$OS_ID" = "rocky" ]
    [ "$OS_MAJOR_VERSION" = "9" ]
}

@test "source_os_release: VERSION_ID with three segments extracts major" {
    cat >"$BATS_TEST_TMPDIR/os-release" <<'EOF'
ID=almalinux
VERSION_ID="9.3.0"
EOF
    export OS_RELEASE_FILE="$BATS_TEST_TMPDIR/os-release"
    source_os_release
    [ "$OS_ID" = "almalinux" ]
    [ "$OS_MAJOR_VERSION" = "9" ]
}

@test "source_os_release: missing VERSION_ID leaves OS_MAJOR_VERSION empty" {
    cat >"$BATS_TEST_TMPDIR/os-release" <<'EOF'
ID=rocky
EOF
    export OS_RELEASE_FILE="$BATS_TEST_TMPDIR/os-release"
    source_os_release
    [ "$OS_ID" = "rocky" ]
    [ -z "$OS_MAJOR_VERSION" ]
}

@test "source_os_release: missing ID aborts" {
    cat >"$BATS_TEST_TMPDIR/os-release" <<'EOF'
NAME="No ID Field"
VERSION_ID="9"
EOF
    export OS_RELEASE_FILE="$BATS_TEST_TMPDIR/os-release"
    run source_os_release
    [ "$status" -ne 0 ]
    [[ "$output" == *"missing ID"* ]]
}

@test "source_os_release: blank file aborts" {
    : >"$BATS_TEST_TMPDIR/os-release"
    export OS_RELEASE_FILE="$BATS_TEST_TMPDIR/os-release"
    run source_os_release
    [ "$status" -ne 0 ]
}

@test "source_os_release: does not leak sibling os-release fields into env" {
    # Sanity check that the subshell trick in platform.sh keeps noisy
    # fields (NAME, PRETTY_NAME, BUILD_ID) out of the caller's env.
    make_os_release "ubuntu" "24.04" "Ubuntu 24.04 LTS"
    # Pre-unset a field set by make_os_release — we want to prove
    # source_os_release doesn't re-introduce it.
    unset NAME PRETTY_NAME
    source_os_release
    [ -z "${NAME:-}" ]
    [ -z "${PRETTY_NAME:-}" ]
}

# ---- die_if_unsupported_os boundary cases ----------------------------------

@test "die_if_unsupported_os: Rocky 10 (future major) aborts" {
    make_os_release "rocky" "10.0"
    run die_if_unsupported_os
    [ "$status" -ne 0 ]
    [[ "$output" == *"unsupported OS"* ]]
}

@test "die_if_unsupported_os: Ubuntu 26.04 (future major) aborts" {
    make_os_release "ubuntu" "26.04"
    run die_if_unsupported_os
    [ "$status" -ne 0 ]
    [[ "$output" == *"unsupported OS"* ]]
}

@test "die_if_unsupported_os: Fedora rejects (not in supported set)" {
    make_os_release "fedora" "40"
    run die_if_unsupported_os
    [ "$status" -ne 0 ]
    [[ "$output" == *"unsupported OS"* ]]
    [[ "$output" == *"fedora"* ]]
}

@test "die_if_unsupported_os: Centos 9 (close to Rocky but not supported) aborts" {
    make_os_release "centos" "9"
    run die_if_unsupported_os
    [ "$status" -ne 0 ]
    [[ "$output" == *"unsupported OS"* ]]
}

@test "die_if_unsupported_os: AlmaLinux 9 aborts (only Rocky 9 is whitelisted)" {
    make_os_release "almalinux" "9.3"
    run die_if_unsupported_os
    [ "$status" -ne 0 ]
    [[ "$output" == *"unsupported OS"* ]]
}
