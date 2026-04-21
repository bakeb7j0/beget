#!/usr/bin/env bats
# tests/unit/tooling.bats — unit tests for the seven tool-install scripts
# under run_onchange_before_5{0..6}-tool-*.sh.
#
# Strategy: each script exposes env-var seams so we can redirect file
# system targets to $BATS_TEST_TMPDIR and replace curl/sha256sum/pipx/uv
# with stub shims whose behaviour we control. No network. No sudo.

setup() {
    REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
    DOWNLOAD_SCRIPT="$REPO_ROOT/run_onchange_before_50-tool-download-binaries.sh"
    SHELL_SCRIPT="$REPO_ROOT/run_onchange_before_51-tool-shell-installers.sh"
    PIPX_SCRIPT="$REPO_ROOT/run_onchange_before_52-tool-pipx.sh"
    UV_SCRIPT="$REPO_ROOT/run_onchange_before_53-tool-uv.sh"
    CLAUDE_SCRIPT="$REPO_ROOT/run_onchange_before_54-tool-claude-code.sh"
    CARBONYL_SCRIPT="$REPO_ROOT/run_onchange_before_55-tool-carbonyl.sh"
    GO_SCRIPT="$REPO_ROOT/run_onchange_before_56-tool-go.sh"

    # Shared scratch layout: bin dir (fake ~/.local/bin) and a log we use
    # to observe stub invocations from inside the scripts.
    export BEGET_BIN_DIR="$BATS_TEST_TMPDIR/bin"
    mkdir -p "$BEGET_BIN_DIR"
    export STUB_LOG="$BATS_TEST_TMPDIR/stub.log"
    : > "$STUB_LOG"
}

# --- 50-tool-download-binaries -----------------------------------------------

@test "50: beget_tool_table lists 12 tools" {
    # Source and invoke the pure function.
    # shellcheck disable=SC1090
    source "$DOWNLOAD_SCRIPT" </dev/null || true
    run beget_tool_table
    [ "$status" -eq 0 ]
    local n
    n=$(printf '%s\n' "$output" | grep -cE '^[a-z]' || true)
    [ "${n:-0}" = "12" ]
}

@test "50: current_version_matches returns 1 when binary absent" {
    # shellcheck disable=SC1090
    source "$DOWNLOAD_SCRIPT" </dev/null || true
    run current_version_matches yq 4.44.1
    [ "$status" -ne 0 ]
}

@test "50: current_version_matches returns 0 on matching --version output" {
    cat > "$BEGET_BIN_DIR/yq" <<'EOF'
#!/usr/bin/env bash
echo "yq (https://github.com/mikefarah/yq/) version 4.44.1"
EOF
    chmod +x "$BEGET_BIN_DIR/yq"
    # shellcheck disable=SC1090
    source "$DOWNLOAD_SCRIPT" </dev/null || true
    run current_version_matches yq 4.44.1
    [ "$status" -eq 0 ]
}

@test "50: install_download_binary aborts on sha256 mismatch" {
    # Stub curl to write a byte, sha256sum to print a bogus hash.
    cat > "$BATS_TEST_TMPDIR/curl" <<'EOF'
#!/usr/bin/env bash
# Accept -fsSL -o PATH URL
while [[ $# -gt 0 ]]; do
  case "$1" in
    -o) out="$2"; shift 2 ;;
    *) shift ;;
  esac
done
printf 'X' > "$out"
EOF
    chmod +x "$BATS_TEST_TMPDIR/curl"
    cat > "$BATS_TEST_TMPDIR/fake-sha256sum" <<'EOF'
#!/usr/bin/env bash
echo "deadbeef $1"
EOF
    chmod +x "$BATS_TEST_TMPDIR/fake-sha256sum"
    export BEGET_CURL="$BATS_TEST_TMPDIR/curl"
    export BEGET_SHA256SUM="$BATS_TEST_TMPDIR/fake-sha256sum"
    # shellcheck disable=SC1090
    source "$DOWNLOAD_SCRIPT" </dev/null || true
    run install_download_binary yq 4.44.1 https://example/yq expectedhash
    [ "$status" -ne 0 ]
    [[ "$output" == *"checksum mismatch"* ]]
}

@test "50: install_download_binary succeeds when sha matches" {
    cat > "$BATS_TEST_TMPDIR/curl" <<'EOF'
#!/usr/bin/env bash
while [[ $# -gt 0 ]]; do
  case "$1" in
    -o) out="$2"; shift 2 ;;
    *) shift ;;
  esac
done
printf 'YQBIN' > "$out"
EOF
    chmod +x "$BATS_TEST_TMPDIR/curl"
    cat > "$BATS_TEST_TMPDIR/fake-sha256sum" <<'EOF'
#!/usr/bin/env bash
echo "matchinghash $1"
EOF
    chmod +x "$BATS_TEST_TMPDIR/fake-sha256sum"
    export BEGET_CURL="$BATS_TEST_TMPDIR/curl"
    export BEGET_SHA256SUM="$BATS_TEST_TMPDIR/fake-sha256sum"
    # shellcheck disable=SC1090
    source "$DOWNLOAD_SCRIPT" </dev/null || true
    run install_download_binary yq 4.44.1 https://example/yq matchinghash
    [ "$status" -eq 0 ]
    [ -x "$BEGET_BIN_DIR/yq" ]
}

@test "50: classify_artifact detects tar.gz/zip/raw by URL suffix" {
    # shellcheck disable=SC1090
    source "$DOWNLOAD_SCRIPT" </dev/null || true
    [ "$(classify_artifact https://e/trivy_0.52.0_Linux-64bit.tar.gz)" = "tar.gz" ]
    [ "$(classify_artifact https://e/rclone-v1.66.0-linux-amd64.zip)"  = "zip" ]
    [ "$(classify_artifact https://e/kubectl)"                         = "raw" ]
    [ "$(classify_artifact https://e/yq_linux_amd64)"                  = "raw" ]
    [ "$(classify_artifact https://e/tool.TGZ)"                        = "tar.gz" ]
}

@test "50: install_download_binary extracts tar.gz and installs inner binary" {
    # Build a real tar.gz fixture containing a file named 'trivy'.
    local srcdir="$BATS_TEST_TMPDIR/trivy-src"
    mkdir -p "$srcdir"
    printf '#!/usr/bin/env bash\necho trivy v0.52.0\n' > "$srcdir/trivy"
    chmod +x "$srcdir/trivy"
    ( cd "$srcdir" && tar -czf "$BATS_TEST_TMPDIR/trivy.tar.gz" trivy )

    # Stub curl to serve the archive bytes. Stub sha256sum to accept any hash.
    cat > "$BATS_TEST_TMPDIR/curl" <<EOF
#!/usr/bin/env bash
while [[ \$# -gt 0 ]]; do
  case "\$1" in
    -o) out="\$2"; shift 2 ;;
    *) shift ;;
  esac
done
cp "$BATS_TEST_TMPDIR/trivy.tar.gz" "\$out"
EOF
    chmod +x "$BATS_TEST_TMPDIR/curl"
    cat > "$BATS_TEST_TMPDIR/fake-sha256sum" <<'EOF'
#!/usr/bin/env bash
echo "expected $1"
EOF
    chmod +x "$BATS_TEST_TMPDIR/fake-sha256sum"
    export BEGET_CURL="$BATS_TEST_TMPDIR/curl"
    export BEGET_SHA256SUM="$BATS_TEST_TMPDIR/fake-sha256sum"

    # shellcheck disable=SC1090
    source "$DOWNLOAD_SCRIPT" </dev/null || true
    run install_download_binary trivy 0.52.0 https://example/trivy.tar.gz expected
    [ "$status" -eq 0 ]
    [ -x "$BEGET_BIN_DIR/trivy" ]
    # Installed binary must be the one packed in the tarball, not the archive.
    grep -q 'trivy v0.52.0' "$BEGET_BIN_DIR/trivy"
}

@test "50: install_download_binary extracts zip and installs inner binary" {
    # Stub unzip: when called as `unzip -q ARCHIVE -d DEST`, copy a staged
    # tree into DEST. This exercises the script's zip branch without
    # depending on the `zip` CLI being installed on the test host.
    local staged="$BATS_TEST_TMPDIR/bw-staged"
    mkdir -p "$staged"
    printf '#!/usr/bin/env bash\necho bw 2024.5.0\n' > "$staged/bw"
    chmod +x "$staged/bw"

    cat > "$BATS_TEST_TMPDIR/fake-unzip" <<EOF
#!/usr/bin/env bash
# Real unzip contract: \`unzip -q <archive> -d <dest>\` — archive is the
# first non-flag positional; <dest> follows -d. The stub FAILS if either
# is missing so a regression in the production invocation surfaces as a
# test failure instead of silently passing.
set -e
archive=""
dest=""
while [[ \$# -gt 0 ]]; do
  case "\$1" in
    -q) shift ;;
    -d) dest="\$2"; shift 2 ;;
    -*) shift ;;  # unknown flag
    *)  archive="\$1"; shift ;;
  esac
done
[[ -n "\$archive" && -s "\$archive" ]] || { echo "fake-unzip: missing/empty archive arg" >&2; exit 2; }
[[ -n "\$dest" && -d "\$dest"    ]] || { echo "fake-unzip: missing -d dest"           >&2; exit 2; }
cp -r "$staged"/. "\$dest"/
EOF
    chmod +x "$BATS_TEST_TMPDIR/fake-unzip"

    cat > "$BATS_TEST_TMPDIR/curl" <<'EOF'
#!/usr/bin/env bash
while [[ $# -gt 0 ]]; do
  case "$1" in
    -o) out="$2"; shift 2 ;;
    *) shift ;;
  esac
done
printf 'zipbytes' > "$out"
EOF
    chmod +x "$BATS_TEST_TMPDIR/curl"
    cat > "$BATS_TEST_TMPDIR/fake-sha256sum" <<'EOF'
#!/usr/bin/env bash
echo "expected $1"
EOF
    chmod +x "$BATS_TEST_TMPDIR/fake-sha256sum"
    export BEGET_CURL="$BATS_TEST_TMPDIR/curl"
    export BEGET_SHA256SUM="$BATS_TEST_TMPDIR/fake-sha256sum"
    export BEGET_UNZIP="$BATS_TEST_TMPDIR/fake-unzip"

    # shellcheck disable=SC1090
    source "$DOWNLOAD_SCRIPT" </dev/null || true
    run install_download_binary bw 2024.5.0 https://example/bw.zip expected
    [ "$status" -eq 0 ]
    [ -x "$BEGET_BIN_DIR/bw" ]
    grep -q 'bw 2024.5.0' "$BEGET_BIN_DIR/bw"
}

@test "50: install_download_binary routes aws zip through aws/install bootstrap" {
    # Stage extracted tree with aws/install as an executable that
    # records its arguments — stands in for the real AWS CLI installer.
    local staged="$BATS_TEST_TMPDIR/aws-staged"
    mkdir -p "$staged/aws"
    cat > "$staged/aws/install" <<EOF
#!/usr/bin/env bash
echo "aws-installer-ran \$*" > "$BATS_TEST_TMPDIR/aws.invoked"
EOF
    chmod +x "$staged/aws/install"

    cat > "$BATS_TEST_TMPDIR/fake-unzip" <<EOF
#!/usr/bin/env bash
# Same contract as the bw test: require archive + -d dest, fail loudly
# if production's invocation shape ever regresses.
set -e
archive=""
dest=""
while [[ \$# -gt 0 ]]; do
  case "\$1" in
    -q) shift ;;
    -d) dest="\$2"; shift 2 ;;
    -*) shift ;;
    *)  archive="\$1"; shift ;;
  esac
done
[[ -n "\$archive" && -s "\$archive" ]] || { echo "fake-unzip: missing/empty archive arg" >&2; exit 2; }
[[ -n "\$dest" && -d "\$dest"    ]] || { echo "fake-unzip: missing -d dest"           >&2; exit 2; }
cp -r "$staged"/. "\$dest"/
EOF
    chmod +x "$BATS_TEST_TMPDIR/fake-unzip"

    cat > "$BATS_TEST_TMPDIR/curl" <<'EOF'
#!/usr/bin/env bash
while [[ $# -gt 0 ]]; do
  case "$1" in
    -o) out="$2"; shift 2 ;;
    *) shift ;;
  esac
done
printf 'zipbytes' > "$out"
EOF
    chmod +x "$BATS_TEST_TMPDIR/curl"
    cat > "$BATS_TEST_TMPDIR/fake-sha256sum" <<'EOF'
#!/usr/bin/env bash
echo "expected $1"
EOF
    chmod +x "$BATS_TEST_TMPDIR/fake-sha256sum"
    export BEGET_CURL="$BATS_TEST_TMPDIR/curl"
    export BEGET_SHA256SUM="$BATS_TEST_TMPDIR/fake-sha256sum"
    export BEGET_UNZIP="$BATS_TEST_TMPDIR/fake-unzip"
    # Pin HOME to tmpdir so --install-dir doesn't write to the real $HOME.
    export HOME="$BATS_TEST_TMPDIR"

    # shellcheck disable=SC1090
    source "$DOWNLOAD_SCRIPT" </dev/null || true
    run install_download_binary aws 2.15.30 https://example/aws.zip expected
    [ "$status" -eq 0 ]
    [ -f "$BATS_TEST_TMPDIR/aws.invoked" ]
    grep -q '\-\-install-dir' "$BATS_TEST_TMPDIR/aws.invoked"
    grep -q '\-\-bin-dir'     "$BATS_TEST_TMPDIR/aws.invoked"
}

@test "50: install_download_binary fails cleanly when tar.gz lacks expected binary" {
    # Build a tar.gz that contains the WRONG inner filename.
    local srcdir="$BATS_TEST_TMPDIR/wrong-src"
    mkdir -p "$srcdir"
    printf 'nope' > "$srcdir/something-else"
    ( cd "$srcdir" && tar -czf "$BATS_TEST_TMPDIR/wrong.tar.gz" something-else )

    cat > "$BATS_TEST_TMPDIR/curl" <<EOF
#!/usr/bin/env bash
while [[ \$# -gt 0 ]]; do
  case "\$1" in
    -o) out="\$2"; shift 2 ;;
    *) shift ;;
  esac
done
cp "$BATS_TEST_TMPDIR/wrong.tar.gz" "\$out"
EOF
    chmod +x "$BATS_TEST_TMPDIR/curl"
    cat > "$BATS_TEST_TMPDIR/fake-sha256sum" <<'EOF'
#!/usr/bin/env bash
echo "expected $1"
EOF
    chmod +x "$BATS_TEST_TMPDIR/fake-sha256sum"
    export BEGET_CURL="$BATS_TEST_TMPDIR/curl"
    export BEGET_SHA256SUM="$BATS_TEST_TMPDIR/fake-sha256sum"
    # shellcheck disable=SC1090
    source "$DOWNLOAD_SCRIPT" </dev/null || true
    run install_download_binary trivy 0.52.0 https://example/wrong.tar.gz expected
    [ "$status" -ne 0 ]
    [[ "$output" == *"no binary named trivy"* ]]
    [ ! -e "$BEGET_BIN_DIR/trivy" ]
}

@test "50: main with non-matching BEGET_TOOL_FILTER skips all tools" {
    # Contract: BEGET_TOOL_FILTER, when non-empty, is a strict allowlist.
    # A filter token that matches no row → every row filtered out → no
    # download attempts → exit 0 with no side-effects.
    export BEGET_DRY_RUN=1
    export BEGET_TOOL_FILTER="__none__"
    # Stub curl so any accidental fetch would be caught.
    cat > "$BATS_TEST_TMPDIR/curl-guard" <<'EOF'
#!/usr/bin/env bash
echo "UNEXPECTED curl call: $*" >&2
exit 99
EOF
    chmod +x "$BATS_TEST_TMPDIR/curl-guard"
    export BEGET_CURL="$BATS_TEST_TMPDIR/curl-guard"
    run bash "$DOWNLOAD_SCRIPT"
    [ "$status" -eq 0 ]
}

# --- 51-tool-shell-installers ------------------------------------------------

@test "51: skips when marker dir exists" {
    # Pre-create the three marker dirs → no installer should run.
    mkdir -p "$BATS_TEST_TMPDIR/home/.cargo" \
             "$BATS_TEST_TMPDIR/home/.bun" \
             "$BATS_TEST_TMPDIR/home/.nvm"
    export BEGET_HOME="$BATS_TEST_TMPDIR/home"
    # curl is stubbed to fail loudly if invoked.
    cat > "$BATS_TEST_TMPDIR/curl" <<'EOF'
#!/usr/bin/env bash
echo "UNEXPECTED curl call with: $*" >&2
exit 99
EOF
    chmod +x "$BATS_TEST_TMPDIR/curl"
    export BEGET_CURL="$BATS_TEST_TMPDIR/curl"
    run bash "$SHELL_SCRIPT"
    [ "$status" -eq 0 ]
    [[ "$output" == *"rustup already present"* ]]
    [[ "$output" == *"bun already present"* ]]
    [[ "$output" == *"nvm already present"* ]]
}

@test "51: dry-run iterates all three without exec" {
    export BEGET_HOME="$BATS_TEST_TMPDIR/home"
    mkdir -p "$BEGET_HOME"
    export BEGET_SHELL_INSTALLERS_DRY_RUN=1
    run bash "$SHELL_SCRIPT"
    [ "$status" -eq 0 ]
    [[ "$output" == *"DRY-RUN would install rustup"* ]]
    [[ "$output" == *"DRY-RUN would install bun"* ]]
    [[ "$output" == *"DRY-RUN would install nvm"* ]]
}

# --- 52-tool-pipx ------------------------------------------------------------

@test "52: missing pipx fails with diagnostic" {
    export BEGET_PIPX="$BATS_TEST_TMPDIR/does-not-exist"
    run bash "$PIPX_SCRIPT"
    [ "$status" -ne 0 ]
    [[ "$output" == *"not found on PATH"* ]]
}

@test "52: skips already-installed packages" {
    cat > "$BATS_TEST_TMPDIR/fake-pipx" <<'EOF'
#!/usr/bin/env bash
case "$1" in
    list)
        # Report all 4 target packages already installed.
        echo "yamllint 1.35"
        echo "yt-dlp 2024.05.27"
        echo "gl-settings 0.1.0"
        echo "kairos-contracts 0.2.0"
        ;;
    install)
        echo "UNEXPECTED install $2" >&2
        exit 99
        ;;
esac
EOF
    chmod +x "$BATS_TEST_TMPDIR/fake-pipx"
    export BEGET_PIPX="$BATS_TEST_TMPDIR/fake-pipx"
    run bash "$PIPX_SCRIPT"
    [ "$status" -eq 0 ]
    [[ "$output" == *"yamllint already installed"* ]]
    [[ "$output" == *"yt-dlp already installed"* ]]
    [[ "$output" == *"gl-settings already installed"* ]]
    [[ "$output" == *"kairos-contracts already installed"* ]]
}

@test "52: dry-run installs none" {
    cat > "$BATS_TEST_TMPDIR/fake-pipx" <<'EOF'
#!/usr/bin/env bash
# Empty `pipx list --short` → nothing installed → should trigger dry-run-install.
case "$1" in
    list) echo "" ;;
    install) echo "UNEXPECTED install $2" >&2; exit 99 ;;
esac
EOF
    chmod +x "$BATS_TEST_TMPDIR/fake-pipx"
    export BEGET_PIPX="$BATS_TEST_TMPDIR/fake-pipx"
    export BEGET_PIPX_DRY_RUN=1
    run bash "$PIPX_SCRIPT"
    [ "$status" -eq 0 ]
    [[ "$output" == *"DRY-RUN would install yamllint"* ]]
}

# --- 53-tool-uv --------------------------------------------------------------

@test "53: missing uv fails with diagnostic" {
    export BEGET_UV="$BATS_TEST_TMPDIR/does-not-exist"
    run bash "$UV_SCRIPT"
    [ "$status" -ne 0 ]
    [[ "$output" == *"not found on PATH"* ]]
}

@test "53: skips already-installed dvc" {
    cat > "$BATS_TEST_TMPDIR/fake-uv" <<'EOF'
#!/usr/bin/env bash
case "$1" in
    tool)
        case "$2" in
            list) echo "dvc v3.50.0" ;;
            install) echo "UNEXPECTED install $3" >&2; exit 99 ;;
        esac
        ;;
esac
EOF
    chmod +x "$BATS_TEST_TMPDIR/fake-uv"
    export BEGET_UV="$BATS_TEST_TMPDIR/fake-uv"
    run bash "$UV_SCRIPT"
    [ "$status" -eq 0 ]
    [[ "$output" == *"dvc already installed"* ]]
}

@test "53: dry-run lists target without installing" {
    # `uv tool list` returns empty → not-installed → dry-run path fires.
    cat > "$BATS_TEST_TMPDIR/fake-uv" <<'EOF'
#!/usr/bin/env bash
case "$1" in
    tool)
        case "$2" in
            list) echo "" ;;
            install) echo "UNEXPECTED install $3" >&2; exit 99 ;;
        esac
        ;;
esac
EOF
    chmod +x "$BATS_TEST_TMPDIR/fake-uv"
    export BEGET_UV="$BATS_TEST_TMPDIR/fake-uv"
    export BEGET_UV_DRY_RUN=1
    run bash "$UV_SCRIPT"
    [ "$status" -eq 0 ]
    [[ "$output" == *"DRY-RUN would install dvc"* ]]
}

# --- 54-tool-claude-code -----------------------------------------------------

@test "54: skips when binary present" {
    cat > "$BEGET_BIN_DIR/claude" <<'EOF'
#!/usr/bin/env bash
echo 1.0
EOF
    chmod +x "$BEGET_BIN_DIR/claude"
    run bash "$CLAUDE_SCRIPT"
    [ "$status" -eq 0 ]
    [[ "$output" == *"skipping"* ]]
}

@test "54: BEGET_CLAUDE_CODE_SKIP=1 skips entirely" {
    BEGET_CLAUDE_CODE_SKIP=1 run bash "$CLAUDE_SCRIPT"
    [ "$status" -eq 0 ]
    [[ "$output" == *"skipping"* ]]
}

@test "54: dry-run reports URL without curl" {
    # Ensure no claude binary, no skip.
    rm -f "$BEGET_BIN_DIR/claude"
    cat > "$BATS_TEST_TMPDIR/curl" <<'EOF'
#!/usr/bin/env bash
echo "UNEXPECTED curl call" >&2
exit 99
EOF
    chmod +x "$BATS_TEST_TMPDIR/curl"
    export BEGET_CURL="$BATS_TEST_TMPDIR/curl"
    export BEGET_CLAUDE_CODE_DRY_RUN=1
    run bash "$CLAUDE_SCRIPT"
    [ "$status" -eq 0 ]
    [[ "$output" == *"DRY-RUN would install"* ]]
}

# --- 55-tool-carbonyl --------------------------------------------------------

@test "55: skips when --version matches" {
    cat > "$BEGET_BIN_DIR/carbonyl" <<'EOF'
#!/usr/bin/env bash
echo "carbonyl 0.0.3"
EOF
    chmod +x "$BEGET_BIN_DIR/carbonyl"
    export BEGET_CARBONYL_VERSION=0.0.3
    run bash "$CARBONYL_SCRIPT"
    [ "$status" -eq 0 ]
    [[ "$output" == *"already current"* ]]
}

@test "55: checksum mismatch aborts" {
    rm -f "$BEGET_BIN_DIR/carbonyl"
    cat > "$BATS_TEST_TMPDIR/curl" <<'EOF'
#!/usr/bin/env bash
while [[ $# -gt 0 ]]; do
  case "$1" in
    -o) out="$2"; shift 2 ;;
    *) shift ;;
  esac
done
printf 'fake-tarball' > "$out"
EOF
    chmod +x "$BATS_TEST_TMPDIR/curl"
    cat > "$BATS_TEST_TMPDIR/fake-sha256sum" <<'EOF'
#!/usr/bin/env bash
echo "wronghash $1"
EOF
    chmod +x "$BATS_TEST_TMPDIR/fake-sha256sum"
    export BEGET_CURL="$BATS_TEST_TMPDIR/curl"
    export BEGET_SHA256SUM="$BATS_TEST_TMPDIR/fake-sha256sum"
    export BEGET_CARBONYL_SHA256="expectedhash"
    run bash "$CARBONYL_SCRIPT"
    [ "$status" -ne 0 ]
    [[ "$output" == *"checksum mismatch"* ]]
}

@test "55: dry-run skips network work" {
    rm -f "$BEGET_BIN_DIR/carbonyl"
    export BEGET_CARBONYL_DRY_RUN=1
    run bash "$CARBONYL_SCRIPT"
    [ "$status" -eq 0 ]
    [[ "$output" == *"DRY-RUN would fetch"* ]]
}

# --- 56-tool-go --------------------------------------------------------------

@test "56: skips when go version matches" {
    # Fake go tree reporting the expected version.
    local root="$BATS_TEST_TMPDIR/go-root"
    mkdir -p "$root/bin"
    cat > "$root/bin/go" <<'EOF'
#!/usr/bin/env bash
echo "go version go1.22.3 linux/amd64"
EOF
    chmod +x "$root/bin/go"
    export BEGET_GO_ROOT="$root"
    export BEGET_GO_VERSION=1.22.3
    export BEGET_GO_SKIP_SHFMT=1
    run bash "$GO_SCRIPT"
    [ "$status" -eq 0 ]
    [[ "$output" == *"already installed"* ]]
}

@test "56: dry-run phase-1 skips curl" {
    export BEGET_GO_ROOT="$BATS_TEST_TMPDIR/go-absent"
    export BEGET_GO_DRY_RUN=1
    export BEGET_GO_SKIP_SHFMT=1
    run bash "$GO_SCRIPT"
    [ "$status" -eq 0 ]
    [[ "$output" == *"DRY-RUN would fetch"* ]]
}

@test "56: shfmt phase skippable via env" {
    # go already matches → phase 1 no-ops; phase 2 explicitly skipped.
    local root="$BATS_TEST_TMPDIR/go-root2"
    mkdir -p "$root/bin"
    cat > "$root/bin/go" <<'EOF'
#!/usr/bin/env bash
echo "go version go1.22.3 linux/amd64"
EOF
    chmod +x "$root/bin/go"
    export BEGET_GO_ROOT="$root"
    export BEGET_GO_VERSION=1.22.3
    export BEGET_GO_SKIP_SHFMT=1
    run bash "$GO_SCRIPT"
    [ "$status" -eq 0 ]
    [[ "$output" == *"skipping shfmt"* ]]
}
