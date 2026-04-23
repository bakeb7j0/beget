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
    [[ "$output" == *"--skip-prereqs"* ]]
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

@test "install.sh: parse_flags sets DRY_RUN/ROLE/SKIP_SECRETS/SKIP_APPLY/SKIP_PREREQS/ALLOW_ROOT" {
    source_install
    parse_flags --dry-run --role=minimal --skip-secrets --skip-apply --skip-prereqs --allow-root
    [ "$DRY_RUN" -eq 1 ]
    [ "$ROLE" = "minimal" ]
    [ "$SKIP_SECRETS" -eq 1 ]
    [ "$SKIP_APPLY" -eq 1 ]
    [ "$SKIP_PREREQS" -eq 1 ]
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

# ---- Issue #100: user-local install + preflight root-requirements -----------

@test "install.sh: preflight_root_requirements: missing pinentry on ubuntu dies with exit 3 + remediation" {
    source_install
    # shellcheck source=/dev/null
    source "$REPO_ROOT/lib/platform.sh"
    source "$REPO_ROOT/tests/helpers/mocks.sh"
    make_os_release "ubuntu" "24.04"
    source_os_release
    parse_flags  # defaults: SKIP_PREREQS=0

    # Simulate every distro pkg missing.
    distro_pkg_installed() { return 1; }

    run preflight_root_requirements
    [ "$status" -eq 3 ]
    [[ "$output" == *"missing root-installed prerequisites"* ]]
    [[ "$output" == *"pinentry-curses"* ]]
    [[ "$output" == *"install-prereqs.sh"* ]]
}

@test "install.sh: preflight_root_requirements: all distro prereqs present continues (rc=0)" {
    source_install
    # shellcheck source=/dev/null
    source "$REPO_ROOT/lib/platform.sh"
    source "$REPO_ROOT/tests/helpers/mocks.sh"
    make_os_release "ubuntu" "24.04"
    source_os_release
    parse_flags

    distro_pkg_installed() { return 0; }

    run preflight_root_requirements
    [ "$status" -eq 0 ]
    [[ "$output" == *"distro prereqs OK"* ]]
}

@test "install.sh: preflight_root_requirements: --skip-prereqs bypasses scan entirely" {
    source_install
    # shellcheck source=/dev/null
    source "$REPO_ROOT/lib/platform.sh"
    source "$REPO_ROOT/tests/helpers/mocks.sh"
    make_os_release "ubuntu" "24.04"
    source_os_release
    parse_flags --skip-prereqs

    # If the scan were to run it would invoke distro_pkg_installed; stub it
    # to fail loudly so we catch any bypass regression.
    distro_pkg_installed() { printf 'FAIL: scan ran despite --skip-prereqs\n' >&2; return 99; }

    run preflight_root_requirements
    [ "$status" -eq 0 ]
    [[ "$output" == *"skipping preflight_root_requirements"* ]]
    [[ "$output" != *"FAIL"* ]]
}

@test "install.sh: preflight_root_requirements: rocky without epel lists epel-release + crb enable" {
    source_install
    # shellcheck source=/dev/null
    source "$REPO_ROOT/lib/platform.sh"
    source "$REPO_ROOT/tests/helpers/mocks.sh"
    make_os_release "rocky" "9.3"
    source_os_release
    parse_flags

    # All expected pkgs present except epel-release; CRB disabled.
    distro_pkg_installed() { [[ "$1" != "epel-release" ]]; }
    rocky_repo_enabled() { return 1; }

    run preflight_root_requirements
    [ "$status" -eq 3 ]
    [[ "$output" == *"epel-release"* ]]
    [[ "$output" == *"crb"* ]]
    [[ "$output" == *"install-prereqs.sh"* ]]
}

@test "install.sh + lib/platform.sh: contain zero real sudo calls (regression guard)" {
    # install.sh and lib/platform.sh must never invoke sudo themselves.
    # The only legal occurrences are in comments and in remediation
    # strings that tell the user to run install-prereqs.sh via sudo.
    # Grep for a sudo command-invocation pattern: whitespace or start of
    # line, followed by `sudo`, followed by whitespace + another word.
    # Then filter out commented lines and printf-string instances.
    local hits
    hits="$(grep -nE '(^|[[:space:]])sudo[[:space:]]+[a-zA-Z]' "$REPO_ROOT/install.sh" "$REPO_ROOT/lib/platform.sh" |
        grep -vE '^\s*#|printf .*sudo|^[^:]+:[[:digit:]]+:\s*#' || true)"
    [[ -z "$hits" ]] || {
        printf 'UNEXPECTED sudo calls:\n%s\n' "$hits"
        false
    }
}

@test "install.sh: install_user_local invokes all three upstream installers" {
    source_install
    # shellcheck source=/dev/null
    source "$REPO_ROOT/lib/platform.sh"
    source "$REPO_ROOT/tests/helpers/mocks.sh"
    make_os_release "ubuntu" "24.04"
    source_os_release
    parse_flags --dry-run

    # Replace the three installers with markers so we can assert
    # they were each invoked exactly once.
    local calls="$BATS_TEST_TMPDIR/installer-calls"
    : >"$calls"
    install_chezmoi() { echo chezmoi >>"$calls"; }
    install_direnv() { echo direnv >>"$calls"; }
    install_rbw() { echo rbw >>"$calls"; }
    export -f install_chezmoi install_direnv install_rbw

    run install_user_local
    [ "$status" -eq 0 ]
    run cat "$calls"
    [[ "$output" == *"chezmoi"* ]]
    [[ "$output" == *"direnv"* ]]
    [[ "$output" == *"rbw"* ]]
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
