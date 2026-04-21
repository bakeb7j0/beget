#!/usr/bin/env bats
# tests/unit/apt-repos.bats — unit tests for
# run_onchange_before_10-apt-repos.sh (and companion dnf variant).
#
# We exercise the script via its documented env-var seams: stub curl,
# sudo, and apt-get so we can assert on what would have been written to
# /etc/apt/{keyrings,sources.list.d}/ and that apt-update was invoked
# exactly once.

setup() {
    REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
    SCRIPT="$REPO_ROOT/run_onchange_before_10-apt-repos.sh"
    DNF_SCRIPT="$REPO_ROOT/run_onchange_before_10-dnf-repos.sh"

    export BEGET_APT_KEYRINGS_DIR="$BATS_TEST_TMPDIR/keyrings"
    export BEGET_APT_SOURCES_DIR="$BATS_TEST_TMPDIR/sources.list.d"
    export BEGET_APT_DIST="noble"
    export BEGET_SKIP_APT_UPDATE=1

    mkdir -p "$BEGET_APT_KEYRINGS_DIR" "$BEGET_APT_SOURCES_DIR"

    # Stub sudo to a passthrough (`env $@`) so that `install`/`apt-get`/`rpm`
    # commands execute as the test user against the BATS-owned temp dirs.
    # We can't set BEGET_SUDO="" because the script uses ${BEGET_SUDO:-sudo}
    # which substitutes on null values; instead we pass an explicit command.
    export BEGET_SUDO="env"

    # Stub curl to produce a deterministic keyring body. Successful fetch
    # unless KEYRING_FAIL=1 is set, in which case we exit 22 (like curl -f
    # does on HTTP 4xx).
    cat > "$BATS_TEST_TMPDIR/fake-curl" <<'EOF'
#!/usr/bin/env bash
# Accept curl flags; final non-flag arg pairs: URL + (optional) -o FILE.
# We only care about the URL and the -o destination.
url=""
out=""
while [[ $# -gt 0 ]]; do
    case "$1" in
        -o) out="$2" ; shift 2 ;;
        -*)         shift ;;
        http*)      url="$1" ; shift ;;
        *)          shift ;;
    esac
done
if [[ "${KEYRING_FAIL:-0}" == "1" && "$url" == *"spotify"* ]]; then
    exit 22
fi
# Produce something gpg --dearmor will accept: a minimal ASCII-armored block.
printf -- '-----BEGIN PGP PUBLIC KEY BLOCK-----\n\nmQINBFjQAAAB\n-----END PGP PUBLIC KEY BLOCK-----\n' \
    > "${out:-/dev/stdout}"
EOF
    chmod +x "$BATS_TEST_TMPDIR/fake-curl"
    export BEGET_CURL="$BATS_TEST_TMPDIR/fake-curl"

    # Stub gpg --dearmor so we don't depend on a working gpg in CI.
    export PATH="$BATS_TEST_TMPDIR/bin:$PATH"
    mkdir -p "$BATS_TEST_TMPDIR/bin"
    cat > "$BATS_TEST_TMPDIR/bin/gpg" <<'EOF'
#!/usr/bin/env bash
# Accept stdin, emit a fake binary keyring on stdout.
cat > /dev/null
printf 'FAKEGPG' > /dev/stdout
EOF
    chmod +x "$BATS_TEST_TMPDIR/bin/gpg"
}

@test "script declares 11 repos covering all spec-named sources" {
    # Each repo row is a single line of form NAME|SOURCES|KEYRING in the
    # repos= array. Assert presence of the spec-listed names.
    for name in mozilla google-chrome vivaldi slack spotify wezterm \
                hashicorp vscode synaptics nextcloud-devs xtradeb-apps; do
        grep -q "^\\s*\"${name}|" "$SCRIPT" \
            || { echo "missing repo row: $name" >&2 ; return 1 ; }
    done
}

@test "successful run writes one keyring and one sources file per repo" {
    run bash "$SCRIPT"
    [ "$status" -eq 0 ]
    local keyrings_count sources_count
    keyrings_count=$(find "$BEGET_APT_KEYRINGS_DIR" -name '*.gpg' | wc -l)
    sources_count=$(find "$BEGET_APT_SOURCES_DIR" -name '*.list' | wc -l)
    [ "$keyrings_count" -eq 11 ]
    [ "$sources_count" -eq 11 ]
}

@test "sources files reference signed-by=<keyring path>" {
    run bash "$SCRIPT"
    [ "$status" -eq 0 ]
    local list="$BEGET_APT_SOURCES_DIR/hashicorp.list"
    [ -r "$list" ]
    grep -q "signed-by=${BEGET_APT_KEYRINGS_DIR}/hashicorp.gpg" "$list"
    # {{DIST}} token is substituted with BEGET_APT_DIST.
    grep -q 'noble' "$list"
}

@test "keyrings land under BEGET_APT_KEYRINGS_DIR with 0644 perms" {
    run bash "$SCRIPT"
    [ "$status" -eq 0 ]
    local kr="$BEGET_APT_KEYRINGS_DIR/mozilla.gpg"
    [ -r "$kr" ]
    # Under `install -m 0644` the resulting file is mode 644.
    local perm
    perm=$(stat -c '%a' "$kr")
    [ "$perm" = "644" ]
}

@test "404 on one keyring aborts THAT repo only; no partial sources file" {
    KEYRING_FAIL=1 run bash "$SCRIPT"
    # Overall non-zero exit because at least one repo failed.
    [ "$status" -ne 0 ]
    # spotify should have been skipped; no spotify.list present.
    [ ! -r "$BEGET_APT_SOURCES_DIR/spotify.list" ]
    # Other repos still registered.
    [ -r "$BEGET_APT_SOURCES_DIR/mozilla.list" ]
    [ -r "$BEGET_APT_SOURCES_DIR/hashicorp.list" ]
    # User-facing diagnostic mentions the failed repo.
    [[ "$output" == *"failed to fetch keyring for spotify"* ]]
}

@test "script is idempotent: running twice yields the same filesystem" {
    run bash "$SCRIPT"
    [ "$status" -eq 0 ]
    first=$(find "$BEGET_APT_KEYRINGS_DIR" "$BEGET_APT_SOURCES_DIR" \
        -type f -printf '%p %s\n' | sort)

    run bash "$SCRIPT"
    [ "$status" -eq 0 ]
    second=$(find "$BEGET_APT_KEYRINGS_DIR" "$BEGET_APT_SOURCES_DIR" \
        -type f -printf '%p %s\n' | sort)

    [ "$first" = "$second" ]
}

@test "apt update is invoked exactly once unless BEGET_SKIP_APT_UPDATE=1" {
    unset BEGET_SKIP_APT_UPDATE
    # Force the default (BEGET_APT_UPDATE unset so script rebuilds command from
    # BEGET_SUDO). Guards against a leaked env var from an enclosing shell.
    unset BEGET_APT_UPDATE
    # Stub apt-get to log calls.
    cat > "$BATS_TEST_TMPDIR/bin/apt-get" <<'EOF'
#!/usr/bin/env bash
echo "APT:$*" >> "${APT_LOG}"
EOF
    chmod +x "$BATS_TEST_TMPDIR/bin/apt-get"
    export APT_LOG="$BATS_TEST_TMPDIR/apt.log"
    : > "$APT_LOG"

    run bash "$SCRIPT"
    [ "$status" -eq 0 ]
    # Expect exactly one apt-get update call. `|| echo 0` keeps grep's
    # non-zero exit on zero matches from tripping `set -e` via $(..).
    # grep -c prints 0 and exits 1 on no match; use || true to tolerate.
    local n
    n=$(grep -c 'APT:update' "$APT_LOG" 2>/dev/null || true)
    [ "${n:-0}" = "1" ]
}

@test "dnf variant: declares hashicorp/vscode/google-chrome rows" {
    grep -q '^\s*"hashicorp|' "$DNF_SCRIPT"
    grep -q '^\s*"vscode|' "$DNF_SCRIPT"
    grep -q '^\s*"google-chrome|' "$DNF_SCRIPT"
}

@test "dnf variant: happy-path writes .repo files and skips makecache" {
    export BEGET_YUM_REPOS_DIR="$BATS_TEST_TMPDIR/yum.repos.d"
    export BEGET_SKIP_MAKECACHE=1
    export BEGET_SUDO="env"
    mkdir -p "$BEGET_YUM_REPOS_DIR"

    # Stub rpm to a no-op.
    cat > "$BATS_TEST_TMPDIR/bin/rpm" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
    chmod +x "$BATS_TEST_TMPDIR/bin/rpm"

    run bash "$DNF_SCRIPT"
    [ "$status" -eq 0 ]
    [ -r "$BEGET_YUM_REPOS_DIR/hashicorp.repo" ]
    [ -r "$BEGET_YUM_REPOS_DIR/vscode.repo" ]
    [ -r "$BEGET_YUM_REPOS_DIR/google-chrome.repo" ]
}
