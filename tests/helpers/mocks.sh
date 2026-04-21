#!/usr/bin/env bash
# tests/helpers/mocks.sh — test helpers for platform.sh
#
# Provides make_os_release() to write a mock /etc/os-release file into a
# temp dir and point OS_RELEASE_FILE at it.

# make_os_release <id> <version_id> [pretty_name]
# Writes a minimal os-release file to "$BATS_TEST_TMPDIR/os-release" and
# exports OS_RELEASE_FILE to that path.
make_os_release() {
    local id="$1"
    local version_id="$2"
    local pretty_name="${3:-${id} ${version_id}}"

    local tmpdir="${BATS_TEST_TMPDIR:-${TMPDIR:-/tmp}}"
    local path="${tmpdir}/os-release"

    cat >"$path" <<EOF
NAME="${pretty_name}"
ID=${id}
VERSION_ID="${version_id}"
PRETTY_NAME="${pretty_name}"
EOF

    export OS_RELEASE_FILE="$path"
}

# reset_os_env — clear OS-related env so each test starts fresh.
reset_os_env() {
    unset OS_ID OS_MAJOR_VERSION OS_RELEASE_FILE
}
