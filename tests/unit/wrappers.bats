#!/usr/bin/env bats
# tests/unit/wrappers.bats — unit tests for dot_bashrc.d/executable_50-wrappers.sh
#
# Strategy: source the library, then swap BEGET_RBW_CMD to a shim script
# under BATS_TEST_TMPDIR so rbw calls are deterministic and hermetic.

setup() {
    REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
    WRAPPERS_SH="$REPO_ROOT/dot_bashrc.d/executable_50-wrappers.sh"

    # Shim dir for fake rbw.
    SHIM_DIR="$BATS_TEST_TMPDIR/shim"
    mkdir -p "$SHIM_DIR"
    export BEGET_RBW_CMD="$SHIM_DIR/rbw"

    # Warning capture file so we can assert messages without relying on
    # bats stderr interleaving.
    export BEGET_WARN="$BATS_TEST_TMPDIR/warnings.log"
    : >"$BEGET_WARN"

    # shellcheck source=/dev/null
    source "$WRAPPERS_SH"
}

# Helper: install an rbw shim with given behavior.
#   $1 = behavior keyword: ok | missing | locked | unreachable
#   $2 = (optional) stdout for 'ok' mode
make_rbw() {
    local behavior="$1"
    local out="${2:-secret-value}"
    cat >"$BEGET_RBW_CMD" <<EOF
#!/usr/bin/env bash
# Fake rbw shim for bats tests
case "\${2:-}" in
EOF

    case "$behavior" in
        ok)
            cat >>"$BEGET_RBW_CMD" <<EOF
  *) printf '%s' '$out'; exit 0 ;;
EOF
            ;;
        missing)
            cat >>"$BEGET_RBW_CMD" <<EOF
  *) echo "rbw get: no item named \$2" >&2; exit 1 ;;
EOF
            ;;
        locked)
            cat >>"$BEGET_RBW_CMD" <<EOF
  *) echo "rbw is locked" >&2; exit 2 ;;
EOF
            ;;
        unreachable)
            cat >>"$BEGET_RBW_CMD" <<EOF
  *) echo "rbw: network error" >&2; exit 3 ;;
EOF
            ;;
    esac
    echo "esac" >>"$BEGET_RBW_CMD"
    chmod +x "$BEGET_RBW_CMD"
}

# ---- R-15: name conversion --------------------------------------------------

@test "_secret_file_from_var: GITHUB_PAT -> github-pat" {
    run _secret_file_from_var GITHUB_PAT
    [ "$status" -eq 0 ]
    [ "$output" = "github-pat" ]
}

@test "_secret_file_from_var: GITLAB_TOKEN -> gitlab-token" {
    run _secret_file_from_var GITLAB_TOKEN
    [ "$status" -eq 0 ]
    [ "$output" = "gitlab-token" ]
}

@test "_secret_file_from_var: BAO_TOKEN -> bao-token" {
    run _secret_file_from_var BAO_TOKEN
    [ "$status" -eq 0 ]
    [ "$output" = "bao-token" ]
}

@test "_secret_file_from_var: ANALOGIC_GITLAB_TOKEN -> analogic-gitlab-token" {
    run _secret_file_from_var ANALOGIC_GITLAB_TOKEN
    [ "$status" -eq 0 ]
    [ "$output" = "analogic-gitlab-token" ]
}

@test "_secret_file_from_var: empty input fails" {
    run _secret_file_from_var ""
    [ "$status" -ne 0 ]
}

# ---- R-13: secret() lazy materialization ------------------------------------

@test "secret: materializes from rbw when VAR is empty" {
    make_rbw ok "pat-value-xyz"
    unset GITHUB_PAT
    secret GITHUB_PAT
    [ "$GITHUB_PAT" = "pat-value-xyz" ]
}

@test "secret: skips materialization when VAR already set (R-13)" {
    # Even with a broken rbw, a pre-set VAR must not trigger rbw.
    make_rbw missing
    export GITHUB_PAT="preexisting"
    run secret GITHUB_PAT
    [ "$status" -eq 0 ]
    # Value unchanged.
    [ "$GITHUB_PAT" = "preexisting" ]
    # Nothing was warned, because rbw wasn't called.
    [ ! -s "$BEGET_WARN" ]
}

@test "secret: override arg wins over derived item name" {
    # Shim captures the arg and echos a distinct value only for the
    # override name.
    cat >"$BEGET_RBW_CMD" <<'EOF'
#!/usr/bin/env bash
if [[ "$2" = "analogic-gitlab-token" ]]; then
  printf 'ANALOGIC'
elif [[ "$2" = "gitlab-token" ]]; then
  printf 'PERSONAL'
else
  exit 1
fi
EOF
    chmod +x "$BEGET_RBW_CMD"
    unset GITLAB_TOKEN
    secret GITLAB_TOKEN analogic-gitlab-token
    [ "$GITLAB_TOKEN" = "ANALOGIC" ]
}

@test "secret: missing rbw item -> return 1, warns, env unchanged" {
    make_rbw missing
    unset GITHUB_PAT
    run secret GITHUB_PAT
    [ "$status" -eq 1 ]
    # Warning captured.
    grep -q 'rbw get' "$BEGET_WARN"
}

@test "secret: rbw locked -> return 1" {
    make_rbw locked
    unset GITHUB_PAT
    run secret GITHUB_PAT
    [ "$status" -eq 1 ]
}

@test "secret: rbw unreachable -> return 1" {
    make_rbw unreachable
    unset GITHUB_PAT
    run secret GITHUB_PAT
    [ "$status" -eq 1 ]
}

@test "secret: missing VAR arg -> usage error" {
    run secret
    [ "$status" -eq 1 ]
    grep -q 'usage' "$BEGET_WARN"
}

# ---- R-14: secret_get() prints without exporting ----------------------------

@test "secret_get: prints the value on stdout" {
    make_rbw ok "hello-world"
    run secret_get any-item
    [ "$status" -eq 0 ]
    [ "$output" = "hello-world" ]
}

@test "secret_get: does NOT mutate the env (R-14)" {
    make_rbw ok "hello-world"
    unset GITHUB_PAT
    out="$(secret_get github-pat)"
    [ "$out" = "hello-world" ]
    # GITHUB_PAT must still be unset.
    [ -z "${GITHUB_PAT:-}" ]
}

@test "secret_get: missing item -> return 1" {
    make_rbw missing
    run secret_get nope
    [ "$status" -eq 1 ]
}

@test "secret_get: missing item arg -> usage error" {
    run secret_get
    [ "$status" -eq 1 ]
    grep -q 'usage' "$BEGET_WARN"
}

# ---- R-16: tool wrappers materialize on first call --------------------------

@test "gh wrapper: returns non-zero when GITHUB_PAT cannot be materialized" {
    make_rbw missing
    unset GITHUB_PAT
    # Provide a stub `gh` that would succeed if reached. The wrapper should
    # NOT reach it because secret() fails first.
    local stub_dir="$BATS_TEST_TMPDIR/stubs"
    mkdir -p "$stub_dir"
    cat >"$stub_dir/gh" <<'EOF'
#!/usr/bin/env bash
printf 'REAL_GH_SHOULD_NOT_RUN'
EOF
    chmod +x "$stub_dir/gh"
    PATH="$stub_dir:$PATH"
    run gh pr list
    [ "$status" -eq 1 ]
    [[ "$output" != *"REAL_GH_SHOULD_NOT_RUN"* ]]
}

@test "gh wrapper: materializes GITHUB_PAT on first call, reuses on second (R-16)" {
    # rbw writes a call-count file and returns a unique value per call.
    # We assert that after two gh invocations, rbw was called exactly once
    # and the same GITHUB_PAT was visible to both gh invocations — the
    # correct definition of "materialize once per session, reuse."
    cat >"$BEGET_RBW_CMD" <<'EOF'
#!/usr/bin/env bash
count_file="$BEGET_RBW_COUNT_FILE"
if [[ -f "$count_file" ]]; then
  n=$(cat "$count_file"); n=$((n+1))
else
  n=1
fi
echo "$n" >"$count_file"
printf 'pat-%d' "$n"
EOF
    chmod +x "$BEGET_RBW_CMD"
    export BEGET_RBW_COUNT_FILE="$BATS_TEST_TMPDIR/rbwcount"
    unset GITHUB_PAT

    # Stub the real gh to append the env-visible PAT to a log file.
    local stub_dir="$BATS_TEST_TMPDIR/stubs"
    mkdir -p "$stub_dir"
    export GH_LOG="$BATS_TEST_TMPDIR/ghlog"
    : >"$GH_LOG"
    cat >"$stub_dir/gh" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$GITHUB_PAT" >>"$GH_LOG"
EOF
    chmod +x "$stub_dir/gh"
    PATH="$stub_dir:$PATH"

    # Two calls IN THE CURRENT SHELL — not via `run`, which forks a subshell
    # and would lose the exported GITHUB_PAT between calls.
    gh pr list
    gh pr list
    # rbw must have been called exactly once.
    [ "$(cat "$BEGET_RBW_COUNT_FILE")" = "1" ]
    # Both gh invocations saw the same materialized value.
    mapfile -t seen <"$GH_LOG"
    [ "${#seen[@]}" -eq 2 ]
    [ "${seen[0]}" = "pat-1" ]
    [ "${seen[1]}" = "pat-1" ]
}

@test "glab wrapper: maps to GITLAB_TOKEN, item gitlab-token" {
    cat >"$BEGET_RBW_CMD" <<'EOF'
#!/usr/bin/env bash
[[ "$2" = "gitlab-token" ]] && { printf 'GL'; exit 0; }
exit 1
EOF
    chmod +x "$BEGET_RBW_CMD"
    unset GITLAB_TOKEN
    local stub_dir="$BATS_TEST_TMPDIR/stubs"
    mkdir -p "$stub_dir"
    cat >"$stub_dir/glab" <<'EOF'
#!/usr/bin/env bash
printf 'glab:%s' "$GITLAB_TOKEN"
EOF
    chmod +x "$stub_dir/glab"
    PATH="$stub_dir:$PATH"
    run glab mr list
    [ "$status" -eq 0 ]
    [ "$output" = "glab:GL" ]
}

@test "bao wrapper: maps to BAO_TOKEN, item bao-token" {
    cat >"$BEGET_RBW_CMD" <<'EOF'
#!/usr/bin/env bash
[[ "$2" = "bao-token" ]] && { printf 'BT'; exit 0; }
exit 1
EOF
    chmod +x "$BEGET_RBW_CMD"
    unset BAO_TOKEN
    local stub_dir="$BATS_TEST_TMPDIR/stubs"
    mkdir -p "$stub_dir"
    cat >"$stub_dir/bao" <<'EOF'
#!/usr/bin/env bash
printf 'bao:%s' "$BAO_TOKEN"
EOF
    chmod +x "$stub_dir/bao"
    PATH="$stub_dir:$PATH"
    run bao status
    [ "$status" -eq 0 ]
    [ "$output" = "bao:BT" ]
}

# ---- Self-shellcheck --------------------------------------------------------

@test "wrappers.sh: passes shellcheck" {
    if ! command -v shellcheck >/dev/null 2>&1; then
        skip "shellcheck not installed"
    fi
    run shellcheck -s bash "$WRAPPERS_SH"
    [ "$status" -eq 0 ]
}
