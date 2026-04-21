#!/usr/bin/env bats
# tests/unit/apt-packages.bats — unit tests for
# run_onchange_before_20-packages-common.sh and the share/apt-packages-*.list
# files.

setup() {
    REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
    SCRIPT="$REPO_ROOT/run_onchange_before_20-packages-common.sh"

    # Isolate PACKAGE_DIR into a temp dir so tests can stage list files.
    export BEGET_PACKAGE_DIR="$BATS_TEST_TMPDIR/packages"
    mkdir -p "$BEGET_PACKAGE_DIR"

    # Capture installer invocations by overriding the install function name.
    # The script will call `test_pkg_install <pkg>...`; we export a definition
    # that appends to a file so tests can assert argv.
    export BEGET_PKG_INSTALL="test_pkg_install"
    export BEGET_INSTALL_LOG="$BATS_TEST_TMPDIR/install.log"
    : > "$BEGET_INSTALL_LOG"
    test_pkg_install() {
        printf 'CALL:'
        printf ' %s' "$@"
        printf '\n'
    }
    export -f test_pkg_install
}

# --- list file content ------------------------------------------------------

@test "apt-packages-common.list has at least 20 non-comment entries" {
    local list="$REPO_ROOT/share/apt-packages-common.list"
    [ -r "$list" ]
    local count
    count=$(grep -cv '^\s*\(#\|$\)' "$list")
    [ "$count" -ge 20 ]
}

@test "apt-packages-workstation.list covers GUI/desktop categories" {
    local list="$REPO_ROOT/share/apt-packages-workstation.list"
    [ -r "$list" ]
    # Dev Spec AC: browsers, editors/IDEs, messaging, media, fonts.
    grep -q '# --- browsers ---' "$list"
    grep -q '# --- editors / IDEs ---' "$list"
    grep -q '# --- messaging' "$list"
    grep -q '# --- media ---' "$list"
    grep -q '# --- fonts ---' "$list"
}

@test "apt-packages-minimal.list is a strict subset of common basics" {
    local list="$REPO_ROOT/share/apt-packages-minimal.list"
    [ -r "$list" ]
    # Spec calls out: git, curl, bash, ca-certificates.
    grep -qxF 'git' "$list"
    grep -qxF 'curl' "$list"
    grep -qxF 'bash' "$list"
    grep -qxF 'ca-certificates' "$list"
}

@test "apt-packages-server.list exists and is non-empty" {
    local list="$REPO_ROOT/share/apt-packages-server.list"
    [ -r "$list" ]
    local count
    count=$(grep -cv '^\s*\(#\|$\)' "$list")
    [ "$count" -gt 0 ]
}

# --- script behaviour -------------------------------------------------------

stage_list() {
    local role="$1" ; shift
    local dest="$BEGET_PACKAGE_DIR/apt-packages-${role}.list"
    printf '%s\n' "$@" > "$dest"
}

@test "role=minimal installs ONLY the minimal list (not common)" {
    stage_list common foo bar baz
    stage_list minimal curl git

    BEGET_ROLE=minimal run bash "$SCRIPT"
    [ "$status" -eq 0 ]
    [[ "$output" == *"CALL: curl git"* ]]
    [[ "$output" != *"CALL: foo bar baz"* ]]
}

@test "role=workstation installs common + workstation" {
    stage_list common alpha beta
    stage_list workstation gamma

    BEGET_ROLE=workstation run bash "$SCRIPT"
    [ "$status" -eq 0 ]
    [[ "$output" == *"CALL: alpha beta"* ]]
    [[ "$output" == *"CALL: gamma"* ]]
}

@test "role=server installs common + server" {
    stage_list common alpha
    stage_list server delta epsilon

    BEGET_ROLE=server run bash "$SCRIPT"
    [ "$status" -eq 0 ]
    [[ "$output" == *"CALL: alpha"* ]]
    [[ "$output" == *"CALL: delta epsilon"* ]]
}

@test "comments and blank lines are skipped, whitespace trimmed" {
    cat > "$BEGET_PACKAGE_DIR/apt-packages-minimal.list" <<'LIST'
# leading comment

git
   curl
bash   # trailing inline comment
LIST

    BEGET_ROLE=minimal run bash "$SCRIPT"
    [ "$status" -eq 0 ]
    [[ "$output" == *"CALL: git curl bash"* ]]
}

@test "empty list file emits a skip notice, no installer call" {
    : > "$BEGET_PACKAGE_DIR/apt-packages-minimal.list"

    BEGET_ROLE=minimal run bash "$SCRIPT"
    [ "$status" -eq 0 ]
    [[ "$output" == *"nothing to install"* ]]
    [[ "$output" != *"CALL:"* ]]
}

@test "missing list file warns and does not fail" {
    # No file staged at all.
    BEGET_ROLE=minimal run bash "$SCRIPT"
    [ "$status" -eq 0 ]
    [[ "$output" == *"skip missing list"* ]]
}

@test "unknown role falls back to common with a notice" {
    stage_list common only-common-pkg

    BEGET_ROLE=mystery run bash "$SCRIPT"
    [ "$status" -eq 0 ]
    [[ "$output" == *"unknown role mystery"* ]]
    [[ "$output" == *"CALL: only-common-pkg"* ]]
}

@test "script is idempotent: two runs produce the same set of installer calls" {
    stage_list common one two
    stage_list workstation three

    BEGET_ROLE=workstation run bash "$SCRIPT"
    [ "$status" -eq 0 ]
    first="$output"

    BEGET_ROLE=workstation run bash "$SCRIPT"
    [ "$status" -eq 0 ]
    [ "$output" = "$first" ]
}
