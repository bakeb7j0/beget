#!/usr/bin/env bats
# tests/unit/platform.bats — unit tests for lib/platform.sh

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

@test "source_os_release: Ubuntu 24.04 → OS_ID=ubuntu, OS_MAJOR_VERSION=24" {
    make_os_release "ubuntu" "24.04" "Ubuntu 24.04 LTS"
    source_os_release
    [ "$OS_ID" = "ubuntu" ]
    [ "$OS_MAJOR_VERSION" = "24" ]
}

@test "source_os_release: Rocky 9 → OS_ID=rocky, OS_MAJOR_VERSION=9" {
    make_os_release "rocky" "9.3" "Rocky Linux 9.3"
    source_os_release
    [ "$OS_ID" = "rocky" ]
    [ "$OS_MAJOR_VERSION" = "9" ]
}

@test "source_os_release: Rocky 9 with unquoted version_id" {
    # Some os-release files have VERSION_ID=9 without decimal
    cat >"$BATS_TEST_TMPDIR/os-release" <<EOF
NAME="Rocky Linux"
ID=rocky
VERSION_ID="9"
EOF
    export OS_RELEASE_FILE="$BATS_TEST_TMPDIR/os-release"
    source_os_release
    [ "$OS_ID" = "rocky" ]
    [ "$OS_MAJOR_VERSION" = "9" ]
}

@test "source_os_release: missing file aborts" {
    export OS_RELEASE_FILE="/nonexistent/path/os-release"
    run source_os_release
    [ "$status" -ne 0 ]
    [[ "$output" == *"cannot read os-release"* ]]
}

@test "pkg_install: no args aborts" {
    make_os_release "ubuntu" "24.04"
    run pkg_install
    [ "$status" -ne 0 ]
    [[ "$output" == *"no packages specified"* ]]
}

@test "pkg_install: Ubuntu produces apt-get command" {
    make_os_release "ubuntu" "24.04"
    source_os_release
    # Stub sudo to emit one arg per line so argv boundaries are asserted.
    sudo() { for a in "$@"; do printf 'ARG:%s\n' "$a"; done; }
    export -f sudo
    run pkg_install foo bar
    [ "$status" -eq 0 ]
    [[ "$output" == *"ARG:apt-get"* ]]
    [[ "$output" == *"ARG:install"* ]]
    [[ "$output" == *"ARG:-y"* ]]
    [[ "$output" == *"ARG:foo"* ]]
    [[ "$output" == *"ARG:bar"* ]]
}

@test "pkg_install: Rocky produces dnf command" {
    make_os_release "rocky" "9.3"
    source_os_release
    sudo() { for a in "$@"; do printf 'ARG:%s\n' "$a"; done; }
    export -f sudo
    run pkg_install foo bar
    [ "$status" -eq 0 ]
    [[ "$output" == *"ARG:dnf"* ]]
    [[ "$output" == *"ARG:install"* ]]
    [[ "$output" == *"ARG:-y"* ]]
    [[ "$output" == *"ARG:foo"* ]]
    [[ "$output" == *"ARG:bar"* ]]
}

@test "pkg_install: unsupported OS aborts" {
    make_os_release "arch" "rolling"
    source_os_release
    run pkg_install foo
    [ "$status" -ne 0 ]
    [[ "$output" == *"unsupported OS_ID: arch"* ]]
}

@test "die_if_unsupported_os: Ubuntu 24.04 passes" {
    make_os_release "ubuntu" "24.04"
    run die_if_unsupported_os
    [ "$status" -eq 0 ]
}

@test "die_if_unsupported_os: Rocky 9 passes" {
    make_os_release "rocky" "9.3"
    run die_if_unsupported_os
    [ "$status" -eq 0 ]
}

@test "die_if_unsupported_os: Debian 11 aborts non-zero" {
    make_os_release "debian" "11"
    run die_if_unsupported_os
    [ "$status" -ne 0 ]
    [[ "$output" == *"unsupported OS"* ]]
    [[ "$output" == *"debian"* ]]
}

@test "die_if_unsupported_os: Ubuntu 22.04 (wrong major) aborts non-zero" {
    make_os_release "ubuntu" "22.04"
    run die_if_unsupported_os
    [ "$status" -ne 0 ]
    [[ "$output" == *"unsupported OS"* ]]
}

@test "is_gnome: matches GNOME in XDG_CURRENT_DESKTOP" {
    XDG_CURRENT_DESKTOP="GNOME" run is_gnome
    [ "$status" -eq 0 ]
}

@test "is_gnome: matches case-insensitive gnome" {
    XDG_CURRENT_DESKTOP="ubuntu:GNOME" run is_gnome
    [ "$status" -eq 0 ]
}

@test "is_gnome: returns 1 when XDG_CURRENT_DESKTOP empty" {
    unset XDG_CURRENT_DESKTOP
    run is_gnome
    [ "$status" -eq 1 ]
}

@test "is_gnome: returns 1 for KDE" {
    XDG_CURRENT_DESKTOP="KDE" run is_gnome
    [ "$status" -eq 1 ]
}

@test "pkg_repo_add: missing args aborts" {
    make_os_release "ubuntu" "24.04"
    run pkg_repo_add
    [ "$status" -ne 0 ]
    [[ "$output" == *"usage"* ]]
}

@test "pkg_repo_add: Ubuntu writes .list under APT_SOURCES_DIR" {
    make_os_release "ubuntu" "24.04"
    source_os_release
    export APT_SOURCES_DIR="$BATS_TEST_TMPDIR/apt"
    mkdir -p "$APT_SOURCES_DIR"
    # Stub curl, sudo, gpg, tee so nothing touches the system.
    curl() { printf 'armored-key-bytes'; }
    gpg() {
        # Parse `gpg --dearmor -o <path>` and write a placeholder there.
        local out=""
        while [[ $# -gt 0 ]]; do
            case "$1" in
                -o) out="$2"; shift 2;;
                *)  shift;;
            esac
        done
        cat >/dev/null
        [[ -n "$out" ]] && : >"$out"
    }
    tee() { cat >"$1"; }
    sudo() { "$@"; }
    export -f curl gpg tee sudo
    run pkg_repo_add "https://example.com/apt stable main" \
        "https://example.com/key.asc" "example"
    [ "$status" -eq 0 ]
    [ -f "$APT_SOURCES_DIR/example.list" ]
    grep -q "signed-by=/usr/share/keyrings/example.gpg" "$APT_SOURCES_DIR/example.list"
    grep -q "https://example.com/apt stable main" "$APT_SOURCES_DIR/example.list"
}

@test "pkg_repo_add: Ubuntu aborts when keyring fetch fails" {
    make_os_release "ubuntu" "24.04"
    source_os_release
    export APT_SOURCES_DIR="$BATS_TEST_TMPDIR/apt"
    mkdir -p "$APT_SOURCES_DIR"
    # Stub curl to fail (simulating a 404 or network error).
    curl() { return 22; }
    sudo() { "$@"; }
    export -f curl sudo
    run pkg_repo_add "https://example.com/apt stable main" \
        "https://example.com/key.asc" "example"
    [ "$status" -ne 0 ]
    [[ "$output" == *"failed to fetch keyring"* ]]
    [ ! -f "$APT_SOURCES_DIR/example.list" ]
}

@test "pkg_repo_add: Rocky writes .repo under YUM_REPOS_DIR" {
    make_os_release "rocky" "9.3"
    source_os_release
    export YUM_REPOS_DIR="$BATS_TEST_TMPDIR/yum"
    mkdir -p "$YUM_REPOS_DIR"
    # Stub curl to write the target path (-o path url), sudo to passthru, rpm to noop.
    curl() {
        local out=""
        while [[ $# -gt 0 ]]; do
            case "$1" in
                -o) out="$2"; shift 2;;
                *)  shift;;
            esac
        done
        printf '[example]\nname=example\nbaseurl=https://example.com/rocky/9\n' >"$out"
    }
    rpm() { :; }
    sudo() { "$@"; }
    export -f curl rpm sudo
    run pkg_repo_add "https://example.com/example.repo" \
        "https://example.com/RPM-GPG-KEY-example" "example"
    [ "$status" -eq 0 ]
    [ -f "$YUM_REPOS_DIR/example.repo" ]
    grep -q "baseurl=https://example.com/rocky/9" "$YUM_REPOS_DIR/example.repo"
}
