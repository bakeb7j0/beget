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

@test "pkg_name_pinentry_tty: Ubuntu resolves to pinentry-curses" {
    make_os_release "ubuntu" "24.04"
    source_os_release
    run pkg_name_pinentry_tty
    [ "$status" -eq 0 ]
    [ "$output" = "pinentry-curses" ]
}

@test "pkg_name_pinentry_tty: Debian resolves to pinentry-curses" {
    make_os_release "debian" "12"
    source_os_release
    run pkg_name_pinentry_tty
    [ "$status" -eq 0 ]
    [ "$output" = "pinentry-curses" ]
}

@test "pkg_name_pinentry_tty: Rocky resolves to plain pinentry" {
    make_os_release "rocky" "9.3"
    source_os_release
    run pkg_name_pinentry_tty
    [ "$status" -eq 0 ]
    [ "$output" = "pinentry" ]
}

@test "pkg_name_pinentry_tty: Fedora resolves to plain pinentry" {
    make_os_release "fedora" "39"
    source_os_release
    run pkg_name_pinentry_tty
    [ "$status" -eq 0 ]
    [ "$output" = "pinentry" ]
}

@test "pkg_name_pinentry_tty: unsupported OS aborts" {
    make_os_release "arch" "rolling"
    source_os_release
    run pkg_name_pinentry_tty
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
    export -f cargo

    run install_rbw
    [ "$status" -eq 0 ]
    [[ "$output" == *"already installed"* ]]
    [[ "$output" != *"FAIL"* ]]
}

@test "install_rbw: dry-run logs rustup + cargo install intent without invoking them" {
    # install_rbw no longer installs build deps itself — those come from
    # scripts/install-prereqs.sh and are verified by install.sh's
    # preflight_root_requirements scan. The dry-run path should only log
    # the user-local steps (rustup + cargo install).
    make_os_release "ubuntu" "24.04"
    source_os_release
    local saved_path="$PATH"
    PATH="/nonexistent"
    export DRY_RUN=1

    cargo() { printf 'FAIL: cargo called\n'; return 99; }
    curl() { printf 'FAIL: curl called\n'; return 99; }
    export -f cargo curl

    run install_rbw
    PATH="$saved_path"
    [ "$status" -eq 0 ]
    [[ "$output" == *"[dry-run]"* ]]
    [[ "$output" == *"rust toolchain via rustup"* ]]
    [[ "$output" == *"cargo install rbw"* ]]
    # Build deps must NOT appear — they're not our concern anymore.
    [[ "$output" != *"libssl-dev"* ]]
    [[ "$output" != *"build-essential"* ]]
    [[ "$output" != *"openssl-devel"* ]]
    [[ "$output" != *"FAIL"* ]]
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

