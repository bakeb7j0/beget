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

@test "pkg_ensure_epel: noop on Ubuntu" {
    make_os_release "ubuntu" "24.04"
    source_os_release
    # Fail loudly if any package-manager command is called.
    rpm() { printf 'FAIL: rpm called\n'; return 99; }
    sudo() { printf 'FAIL: sudo called\n'; return 99; }
    export -f rpm sudo
    run pkg_ensure_epel
    [ "$status" -eq 0 ]
    [[ "$output" != *"FAIL"* ]]
}

@test "pkg_ensure_epel: skips epel install but still enables CRB when present" {
    make_os_release "rocky" "9.3"
    source_os_release
    rpm() { return 0; }   # simulate epel-release already installed
    # Track what sudo gets called with; don't fail.
    local calls="$BATS_TEST_TMPDIR/sudo-calls"
    : >"$calls"
    sudo() { printf '%s\n' "$*" >>"$calls"; return 0; }
    export -f rpm sudo
    run pkg_ensure_epel
    [ "$status" -eq 0 ]
    [[ "$output" == *"already installed"* ]]
    # epel-release install must NOT have been invoked; CRB enablement MUST have.
    run cat "$calls"
    [[ "$output" != *"install -y epel-release"* ]]
    [[ "$output" == *"config-manager --set-enabled crb"* ]]
}

@test "pkg_ensure_epel: installs epel-release AND enables CRB when absent" {
    make_os_release "rocky" "9.3"
    source_os_release
    rpm() { return 1; }   # simulate epel-release NOT installed
    local calls="$BATS_TEST_TMPDIR/sudo-calls"
    : >"$calls"
    sudo() { printf '%s\n' "$*" >>"$calls"; return 0; }
    export -f rpm sudo
    run pkg_ensure_epel
    [ "$status" -eq 0 ]
    run cat "$calls"
    [[ "$output" == *"install -y epel-release"* ]]
    [[ "$output" == *"config-manager --set-enabled crb"* ]]
}

@test "pkg_ensure_epel: dry-run on Rocky logs intent without dnf" {
    make_os_release "rocky" "9.3"
    source_os_release
    export DRY_RUN=1
    rpm() { return 1; }   # simulate "not installed"
    sudo() { printf 'FAIL: sudo called\n'; return 99; }
    export -f rpm sudo
    run pkg_ensure_epel
    [ "$status" -eq 0 ]
    [[ "$output" == *"[dry-run]"* ]]
    [[ "$output" == *"epel-release"* ]]
    [[ "$output" == *"crb"* ]]
    [[ "$output" != *"FAIL"* ]]
    unset DRY_RUN
}

@test "install_chezmoi: noop when binary already on PATH" {
    # A stub `chezmoi` on PATH should short-circuit the helper.
    local shimdir="$BATS_TEST_TMPDIR/bin"
    mkdir -p "$shimdir"
    cat >"$shimdir/chezmoi" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
    chmod +x "$shimdir/chezmoi"
    PATH="$shimdir:$PATH"

    # Fail loudly if curl is invoked — it must not be.
    curl() { printf 'FAIL: curl called\n'; return 99; }
    export -f curl

    run install_chezmoi
    [ "$status" -eq 0 ]
    [[ "$output" == *"already installed"* ]]
    [[ "$output" != *"FAIL"* ]]
}

@test "install_chezmoi: dry-run logs intent without invoking curl" {
    # Sandbox PATH so chezmoi is NOT found, forcing the install branch,
    # but keep a reference to the real PATH so bats teardown can still
    # find `rm` and friends after `run`.
    local saved_path="$PATH"
    PATH="/nonexistent"
    export DRY_RUN=1

    curl() { printf 'FAIL: curl called\n'; return 99; }
    export -f curl

    run install_chezmoi
    PATH="$saved_path"
    [ "$status" -eq 0 ]
    [[ "$output" == *"[dry-run]"* ]]
    [[ "$output" == *"get.chezmoi.io"* ]]
    [[ "$output" != *"FAIL"* ]]
    unset DRY_RUN
}

@test "install_chezmoi: aborts when installer fetch fails (R-07)" {
    # Sourced libraries can't set -o pipefail, so a bare `curl | sh` pipe
    # would mask curl failures. Verify the two-step capture pattern surfaces
    # the failure as a non-zero exit plus a clear error message.
    local saved_path="$PATH"
    PATH="/nonexistent"

    curl() { return 22; }
    export -f curl

    run install_chezmoi
    PATH="$saved_path"
    [ "$status" -ne 0 ]
    [[ "$output" == *"failed to fetch installer"* ]]
}

@test "install_direnv: noop when binary already on PATH" {
    local shimdir="$BATS_TEST_TMPDIR/bin"
    mkdir -p "$shimdir"
    cat >"$shimdir/direnv" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
    chmod +x "$shimdir/direnv"
    PATH="$shimdir:$PATH"

    curl() { printf 'FAIL: curl called\n'; return 99; }
    export -f curl

    run install_direnv
    [ "$status" -eq 0 ]
    [[ "$output" == *"already installed"* ]]
    [[ "$output" != *"FAIL"* ]]
}

@test "install_direnv: dry-run logs intent without invoking curl" {
    local saved_path="$PATH"
    PATH="/nonexistent"
    export DRY_RUN=1

    curl() { printf 'FAIL: curl called\n'; return 99; }
    export -f curl

    run install_direnv
    PATH="$saved_path"
    [ "$status" -eq 0 ]
    [[ "$output" == *"[dry-run]"* ]]
    [[ "$output" == *"direnv.net"* ]]
    [[ "$output" != *"FAIL"* ]]
    unset DRY_RUN
}

@test "install_direnv: aborts when installer fetch fails (R-07)" {
    local saved_path="$PATH"
    PATH="/nonexistent"

    curl() { return 22; }
    export -f curl

    run install_direnv
    PATH="$saved_path"
    [ "$status" -ne 0 ]
    [[ "$output" == *"failed to fetch installer"* ]]
}

@test "install_rbw: noop when binary already on PATH" {
    local shimdir="$BATS_TEST_TMPDIR/bin"
    mkdir -p "$shimdir"
    cat >"$shimdir/rbw" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
    chmod +x "$shimdir/rbw"
    PATH="$shimdir:$PATH"

    cargo() { printf 'FAIL: cargo called\n'; return 99; }
    pkg_install() { printf 'FAIL: pkg_install called\n'; return 99; }
    export -f cargo pkg_install

    run install_rbw
    [ "$status" -eq 0 ]
    [[ "$output" == *"already installed"* ]]
    [[ "$output" != *"FAIL"* ]]
}

@test "install_rbw: dry-run logs Ubuntu build deps without invoking cargo or curl" {
    make_os_release "ubuntu" "24.04"
    source_os_release
    local saved_path="$PATH"
    PATH="/nonexistent"
    export DRY_RUN=1

    cargo() { printf 'FAIL: cargo called\n'; return 99; }
    pkg_install() { printf 'FAIL: pkg_install called\n'; return 99; }
    curl() { printf 'FAIL: curl called\n'; return 99; }
    export -f cargo pkg_install curl

    run install_rbw
    PATH="$saved_path"
    [ "$status" -eq 0 ]
    [[ "$output" == *"[dry-run]"* ]]
    [[ "$output" == *"libssl-dev"* ]]
    [[ "$output" == *"build-essential"* ]]
    [[ "$output" == *"rust toolchain via rustup"* ]]
    [[ "$output" == *"cargo install rbw"* ]]
    [[ "$output" != *"FAIL"* ]]
    unset DRY_RUN
}

@test "install_rbw: dry-run logs Rocky build deps (dnf-flavored package names)" {
    make_os_release "rocky" "9.3"
    source_os_release
    local saved_path="$PATH"
    PATH="/nonexistent"
    export DRY_RUN=1

    cargo() { printf 'FAIL: cargo called\n'; return 99; }
    pkg_install() { printf 'FAIL: pkg_install called\n'; return 99; }
    curl() { printf 'FAIL: curl called\n'; return 99; }
    export -f cargo pkg_install curl

    run install_rbw
    PATH="$saved_path"
    [ "$status" -eq 0 ]
    [[ "$output" == *"openssl-devel"* ]]
    [[ "$output" == *"gcc"* ]]
    # Ubuntu-specific packages must NOT appear on Rocky.
    [[ "$output" != *"libssl-dev"* ]]
    [[ "$output" != *"build-essential"* ]]
    unset DRY_RUN
}

@test "ensure_rust_toolchain: noop when rustc ≥ 1.82 already on PATH" {
    local shimdir="$BATS_TEST_TMPDIR/bin"
    mkdir -p "$shimdir"
    cat >"$shimdir/cargo" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
    cat >"$shimdir/rustc" <<'EOF'
#!/usr/bin/env bash
echo "rustc 1.85.0 (abc 2025-01-01)"
EOF
    chmod +x "$shimdir/cargo" "$shimdir/rustc"
    PATH="$shimdir:$PATH"

    curl() { printf 'FAIL: curl called\n'; return 99; }
    export -f curl

    run ensure_rust_toolchain
    [ "$status" -eq 0 ]
    [[ "$output" == *"meets rbw MSRV"* ]]
    [[ "$output" != *"FAIL"* ]]
}

@test "ensure_rust_toolchain: triggers rustup when rustc too old" {
    local shimdir="$BATS_TEST_TMPDIR/bin"
    mkdir -p "$shimdir"
    cat >"$shimdir/cargo" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
    cat >"$shimdir/rustc" <<'EOF'
#!/usr/bin/env bash
echo "rustc 1.75.0 (abc 2024-01-01)"
EOF
    chmod +x "$shimdir/cargo" "$shimdir/rustc"
    PATH="$shimdir:$PATH"

    # Capture the rustup-pipe with stub curl | sh. The function pipes
    # curl output to sh, so replacing both at once is the cleanest seam.
    local marker="$BATS_TEST_TMPDIR/rustup-invoked"
    curl() { printf '#!/bin/sh\ntouch %s\n' "$marker"; }
    sh() { cat | bash "$@"; }
    export -f curl sh

    run ensure_rust_toolchain
    [ "$status" -eq 0 ]
    [[ "$output" == *"below rbw MSRV"* ]]
    [[ "$output" == *"bootstrapping via rustup"* ]]
    [ -f "$marker" ]
}

@test "ensure_rust_toolchain: aborts when rustup fetch fails (R-07)" {
    # Force the rustup-bootstrap branch: no cargo/rustc on PATH, curl
    # fails to download the installer. The function must fail loudly
    # rather than silently proceeding.
    local saved_path="$PATH"
    PATH="/nonexistent"

    curl() { return 22; }
    export -f curl

    run ensure_rust_toolchain
    PATH="$saved_path"
    [ "$status" -ne 0 ]
    [[ "$output" == *"failed to fetch rustup installer"* ]]
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
