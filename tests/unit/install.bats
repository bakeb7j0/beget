#!/usr/bin/env bats
# tests/unit/install.bats — unit tests for install.sh flag parsing + pre-flight

setup() {
    REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
    INSTALL_SH="$REPO_ROOT/install.sh"
}

@test "install.sh: --help prints usage and lists all flags" {
    run bash "$INSTALL_SH" --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"--dry-run"* ]]
    [[ "$output" == *"--role="* ]]
    [[ "$output" == *"--skip-secrets"* ]]
    [[ "$output" == *"--skip-apply"* ]]
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
    # Suppress the top-of-file /dev/tty stdin reparent — tests must be free
    # to run with a controlling terminal attached without install.sh
    # hijacking bats's stdin.
    export BEGET_SKIP_TTY_REPARENT=1
    # shellcheck source=/dev/null
    source "$INSTALL_SH"
}

@test "install.sh: parse_flags sets DRY_RUN/ROLE/SKIP_SECRETS/SKIP_APPLY/ALLOW_ROOT" {
    source_install
    parse_flags --dry-run --role=minimal --skip-secrets --skip-apply --allow-root
    [ "$DRY_RUN" -eq 1 ]
    [ "$ROLE" = "minimal" ]
    [ "$SKIP_SECRETS" -eq 1 ]
    [ "$SKIP_APPLY" -eq 1 ]
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

@test "install.sh: install_prereqs dry-run emits distro and upstream markers" {
    source_install
    parse_flags --dry-run --role=minimal --skip-secrets
    # Source the library so install_prereqs can resolve install_chezmoi /
    # install_rbw / is_gnome. The OS dispatch never executes because
    # DRY_RUN=1, but OS_ID is still needed for install_rbw's guard.
    # shellcheck source=/dev/null
    source "$REPO_ROOT/lib/platform.sh"
    source "$REPO_ROOT/tests/helpers/mocks.sh"
    make_os_release "ubuntu" "24.04"
    source_os_release

    run install_prereqs
    [ "$status" -eq 0 ]
    [[ "$output" == *"would pkg_install"* ]]
    [[ "$output" == *"upstream prereqs"* ]]
    [[ "$output" == *"chezmoi"* ]]
    [[ "$output" == *"rbw"* ]]
}

@test "install.sh: install_prereqs dry-run never invokes real curl or cargo" {
    source_install
    parse_flags --dry-run --role=minimal --skip-secrets
    # shellcheck source=/dev/null
    source "$REPO_ROOT/lib/platform.sh"
    source "$REPO_ROOT/tests/helpers/mocks.sh"
    make_os_release "ubuntu" "24.04"
    source_os_release

    # Stub curl/cargo/sh/pkg_install to fail loudly if the dry-run branch
    # accidentally invokes them. command -v chezmoi / rbw will already
    # return true in the sourced test environment, so we also wipe those
    # via a restricted PATH to force the [dry-run] branch.
    curl() { printf 'FAIL: curl called\n' >&2; return 99; }
    cargo() { printf 'FAIL: cargo called\n' >&2; return 99; }
    pkg_install() { printf 'FAIL: pkg_install called\n' >&2; return 99; }
    export -f curl cargo pkg_install

    # Sandbox PATH so chezmoi / rbw are NOT found — forces the install
    # branch inside install_chezmoi / install_rbw, which should still
    # short-circuit on DRY_RUN=1.
    PATH="/nonexistent" run install_prereqs
    [ "$status" -eq 0 ]
    [[ "$output" != *"FAIL: curl called"* ]]
    [[ "$output" != *"FAIL: cargo called"* ]]
    [[ "$output" != *"FAIL: pkg_install called"* ]]
}

# ---- Issue #98 regression tests ---------------------------------------------
# Coverage for the three stacked bugs that broke the one-liner install on
# fresh machines: broken `rbw status` probe, curl|bash stdin-pipe hazard,
# and --skip-secrets leaking into chezmoi apply.

@test "install.sh: rbw_prompt_if_needed returns 0 when config.json exists" {
    source_install
    parse_flags  # defaults: SKIP_SECRETS=0, DRY_RUN=0

    # Sandbox HOME so the probe hits our fixture instead of the runner's.
    tmp_home="$(mktemp -d)"
    mkdir -p "$tmp_home/.config/rbw"
    printf '{"email":"test@example.com"}\n' >"$tmp_home/.config/rbw/config.json"

    # Stub `rbw` on PATH so `command -v rbw` succeeds without mutating
    # the test machine.
    stub_dir="$(mktemp -d)"
    cat >"$stub_dir/rbw" <<'EOF'
#!/usr/bin/env bash
echo "FAIL: rbw invoked" >&2
exit 1
EOF
    chmod +x "$stub_dir/rbw"

    HOME="$tmp_home" PATH="$stub_dir:$PATH" run rbw_prompt_if_needed
    [ "$status" -eq 0 ]
    [[ "$output" == *"rbw already configured"* ]]
    [[ "$output" != *"FAIL: rbw invoked"* ]]

    rm -rf "$tmp_home" "$stub_dir"
}

@test "install.sh: rbw_prompt_if_needed no longer calls nonexistent 'rbw status'" {
    # Regression test for Bug A — rbw 1.15.0 has no `status` subcommand.
    # Assert the install.sh source text does not reference it.
    run grep -nE '\brbw[[:space:]]+status\b' "$INSTALL_SH"
    [ "$status" -ne 0 ]  # grep returns 1 when no match found (desired)
}

@test "install.sh: preflight errors when no TTY and SKIP_SECRETS=0" {
    source_install
    parse_flags  # defaults: SKIP_SECRETS=0

    # Assert the die message, not the full preflight outcome — preflight
    # also checks required tools and OS. By stubbing stdin to not be a
    # TTY (bats's default), we should hit the die() before any of that.
    # run uses fd 0 from a pipe, so [[ ! -t 0 ]] is true in this context.
    current_euid() { printf '1000\n'; }
    run preflight
    [ "$status" -ne 0 ]
    [[ "$output" == *"no TTY available"* ]]
    [[ "$output" == *"--skip-secrets"* ]]
}

@test "install.sh: preflight TTY check skipped when --skip-secrets" {
    source_install
    parse_flags --skip-secrets
    current_euid() { printf '1000\n'; }
    run preflight
    # Preflight may still fail downstream (network, OS checks) in CI —
    # we only assert the TTY-check branch is NOT hit.
    [[ "$output" != *"no TTY available"* ]]
}

@test "install.sh: write_chezmoi_config writes skip_secrets=true with --skip-secrets" {
    source_install
    parse_flags --skip-secrets
    tmp_home="$(mktemp -d)"
    HOME="$tmp_home" write_chezmoi_config
    [ -f "$tmp_home/.config/chezmoi/chezmoi.toml" ]
    run cat "$tmp_home/.config/chezmoi/chezmoi.toml"
    [[ "$output" == *"skip_secrets = true"* ]]
    rm -rf "$tmp_home"
}

@test "install.sh: write_chezmoi_config writes skip_secrets=false by default" {
    source_install
    parse_flags  # no --skip-secrets
    tmp_home="$(mktemp -d)"
    HOME="$tmp_home" write_chezmoi_config
    [ -f "$tmp_home/.config/chezmoi/chezmoi.toml" ]
    run cat "$tmp_home/.config/chezmoi/chezmoi.toml"
    [[ "$output" == *"skip_secrets = false"* ]]
    rm -rf "$tmp_home"
}

@test "install.sh: write_chezmoi_config respects --dry-run (no file written)" {
    source_install
    parse_flags --dry-run --skip-secrets
    tmp_home="$(mktemp -d)"
    HOME="$tmp_home" run write_chezmoi_config
    [ "$status" -eq 0 ]
    [[ "$output" == *"[dry-run] would write"* ]]
    [ ! -f "$tmp_home/.config/chezmoi/chezmoi.toml" ]
    rm -rf "$tmp_home"
}

@test "install.sh: stdin reparent block is present near top of file" {
    # Guard against someone deleting the fix without noticing.
    # The block must appear within the first 50 lines of install.sh.
    run head -50 "$INSTALL_SH"
    [ "$status" -eq 0 ]
    [[ "$output" == *"exec </dev/tty"* ]]
}

@test "install.sh: stdin reparent honors BEGET_SKIP_TTY_REPARENT" {
    # Smoke test: sourcing install.sh with the test seam set must not
    # reparent our fd 0 (otherwise this bats run would break in odd ways).
    # The source_install helper already sets the env var; verify the
    # block text includes the check.
    run grep -n 'BEGET_SKIP_TTY_REPARENT' "$INSTALL_SH"
    [ "$status" -eq 0 ]
    [[ "$output" == *"-ne 1"* ]]
}
