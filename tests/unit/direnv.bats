#!/usr/bin/env bats
# tests/unit/direnv.bats — unit tests for direnv wiring (S2.6, bakeb7j0/beget#15).
#
# We verify:
#   1. dot_bashrc.d/10-common.sh installs the direnv hook when direnv is on PATH.
#   2. dot_bashrc.d/10-common.sh skips cleanly when direnv is missing.
#   3. dot_config/direnv/direnv.toml exists and declares no [whitelist] table
#      (no implicit auto-approval — explicit `direnv allow` required, R-28).
#   4. install.sh's BASE_PREREQS list includes direnv (R-01).
#   5. dot_local/share/beget/envrc.analogic.example parses under `bash -n` and
#      demonstrates the context-scoped secret pattern (export BEGET_CONTEXT,
#      use of secret_get).

setup() {
    REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
    COMMON="$REPO_ROOT/dot_bashrc.d/10-common.sh"
    DIRENV_TOML="$REPO_ROOT/dot_config/direnv/config.toml"
    INSTALL_SH="$REPO_ROOT/install.sh"
    ENVRC_EXAMPLE="$REPO_ROOT/dot_local/share/beget/envrc.analogic.example"
}

# ---- File presence ----------------------------------------------------------

@test "10-common.sh exists and is readable" {
    [ -r "$COMMON" ]
}

@test "direnv.toml exists and is readable" {
    [ -r "$DIRENV_TOML" ]
}

@test ".envrc example exists and is readable" {
    [ -r "$ENVRC_EXAMPLE" ]
}

# ---- Hook installation ------------------------------------------------------

@test "10-common.sh evaluates direnv hook when direnv is available" {
    # Fake direnv on PATH that echoes a marker when asked to emit its hook.
    shim_dir="$BATS_TEST_TMPDIR/bin"
    mkdir -p "$shim_dir"
    cat >"$shim_dir/direnv" <<'EOF'
#!/usr/bin/env bash
if [ "${1:-}" = "hook" ] && [ "${2:-}" = "bash" ]; then
    printf 'export BEGET_TEST_DIRENV_HOOKED=1\n'
    exit 0
fi
exit 0
EOF
    chmod +x "$shim_dir/direnv"

    # Source 10-common.sh in an isolated shell with the shim on PATH first.
    run bash -c "PATH='$shim_dir:/usr/bin:/bin'; . '$COMMON'; printf '%s' \"\${BEGET_TEST_DIRENV_HOOKED:-unset}\""
    [ "$status" -eq 0 ]
    [ "$output" = "1" ]
}

@test "10-common.sh is a no-op for the direnv block when direnv is missing" {
    # PATH with no direnv — the hook branch should not fire; sourcing still succeeds.
    empty_bin="$BATS_TEST_TMPDIR/empty-bin"
    mkdir -p "$empty_bin"
    run bash -c "PATH='$empty_bin'; . '$COMMON'; printf '%s' \"\${BEGET_TEST_DIRENV_HOOKED:-unset}\""
    [ "$status" -eq 0 ]
    [ "$output" = "unset" ]
}

# ---- direnv.toml policy -----------------------------------------------------

@test "direnv.toml has no [whitelist] section (no implicit auto-approval, R-28)" {
    # A [whitelist] table would bypass the `direnv allow` friction that is
    # the whole point of the policy.
    ! grep -qE '^\s*\[whitelist' "$DIRENV_TOML"
}

@test "direnv.toml declares a [global] section" {
    grep -qE '^\s*\[global\]' "$DIRENV_TOML"
}

# ---- install.sh prereq list -------------------------------------------------

@test "install.sh UPSTREAM_PREREQS list contains direnv (R-01)" {
    # direnv moved from DISTRO_PREREQS to UPSTREAM_PREREQS because
    # Rocky 9 ships it in neither base nor EPEL repos, so the upstream
    # direnv.net installer is the only uniform cross-distro path.
    grep -qE '^readonly UPSTREAM_PREREQS=\(.*\bdirenv\b.*\)' "$INSTALL_SH"
}

# ---- .envrc example quality -------------------------------------------------

@test ".envrc example is syntactically valid bash" {
    run bash -n "$ENVRC_EXAMPLE"
    [ "$status" -eq 0 ]
}

@test ".envrc example sets BEGET_CONTEXT" {
    grep -qE '^export BEGET_CONTEXT=' "$ENVRC_EXAMPLE"
}

@test ".envrc example uses secret_get for context-scoped secret" {
    grep -qE '\$\(secret_get [a-z0-9-]+\)' "$ENVRC_EXAMPLE"
}

@test ".envrc example references analogic-flavored VW item name" {
    grep -qE '(analogic-gitlab-token|AWS_PROFILE=analogic)' "$ENVRC_EXAMPLE"
}

@test ".envrc example passes shellcheck (with direnv/secret_get declared external)" {
    # secret_get is defined at runtime by dot_bashrc.d/50-wrappers.sh; tell
    # shellcheck not to complain about it. PATH_add is a direnv built-in.
    run shellcheck --shell=bash -e SC2155 --exclude=SC2148 "$ENVRC_EXAMPLE"
    [ "$status" -eq 0 ]
}
