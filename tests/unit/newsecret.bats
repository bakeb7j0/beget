#!/usr/bin/env bats
# tests/unit/newsecret.bats — unit tests for dot_local/bin/executable_newsecret
#
# Strategy: swap BEGET_RBW_CMD to a shim script under BATS_TEST_TMPDIR so
# rbw calls are deterministic. Drive newsecret with piped stdin (the
# non-TTY branch) so the tests can assert on exit codes and output.

setup() {
    REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
    NEWSECRET="$REPO_ROOT/dot_local/bin/executable_newsecret"

    SHIM_DIR="$BATS_TEST_TMPDIR/shim"
    mkdir -p "$SHIM_DIR"
    export BEGET_RBW_CMD="$SHIM_DIR/rbw"

    # Record file so we can assert what rbw was called with and what
    # stdin it received.
    export SHIM_LOG="$BATS_TEST_TMPDIR/rbw-calls.log"
    : >"$SHIM_LOG"
}

# Helper: install an rbw shim with a given `get` behavior.
#   $1 = get-behavior: missing (exit 1) | present (exit 0)
#   $2 = add-behavior: ok (exit 0) | fail (exit 1)
make_rbw() {
    local get_behavior="$1"
    local add_behavior="${2:-ok}"

    cat >"$BEGET_RBW_CMD" <<EOF
#!/usr/bin/env bash
# Fake rbw shim for newsecret tests.
sub="\${1:-}"
item="\${2:-}"
case "\$sub" in
  get)
    echo "get \$item" >>"$SHIM_LOG"
    case "$get_behavior" in
      missing) exit 1 ;;
      present) echo "existing-value"; exit 0 ;;
    esac
    ;;
  add)
    # Capture the item name plus the piped value.
    value="\$(cat)"
    echo "add \$item value=\$value" >>"$SHIM_LOG"
    case "$add_behavior" in
      ok)   exit 0 ;;
      fail) echo "rbw add: synthetic failure" >&2; exit 1 ;;
    esac
    ;;
  *)
    echo "unexpected rbw subcommand: \$sub" >&2
    exit 99
    ;;
esac
EOF
    chmod +x "$BEGET_RBW_CMD"
}

# ---- Argument / usage validation -------------------------------------------

@test "no-arg usage prints usage and exits 1" {
    make_rbw missing ok
    run "$NEWSECRET"
    [ "$status" -eq 1 ]
    [[ "$output" == *"usage: newsecret"* ]]
}

@test "too-many args exits 1" {
    make_rbw missing ok
    run "$NEWSECRET" foo bar
    [ "$status" -eq 1 ]
    [[ "$output" == *"usage: newsecret"* ]]
}

@test "whitespace in name is rejected" {
    make_rbw missing ok
    run bash -c "printf 'val\n' | '$NEWSECRET' 'has space'"
    [ "$status" -eq 1 ]
    [[ "$output" == *"whitespace"* ]]
}

# ---- Duplicate detection ---------------------------------------------------

@test "duplicate name reports clear error" {
    make_rbw present ok
    run bash -c "printf 'val\n' | '$NEWSECRET' existing-item"
    [ "$status" -eq 1 ]
    [[ "$output" == *"already exists"* ]]
    [[ "$output" == *"existing-item"* ]]
}

# ---- Empty-value rejection -------------------------------------------------

@test "empty stdin value is rejected" {
    make_rbw missing ok
    run bash -c "printf '' | '$NEWSECRET' new-item"
    [ "$status" -eq 1 ]
    [[ "$output" == *"must not be empty"* ]]
}

# ---- Happy path ------------------------------------------------------------

@test "happy path: rbw add called with piped value; derived env var reported" {
    make_rbw missing ok
    run bash -c "printf 'super-secret-value\n' | '$NEWSECRET' github-pat"
    [ "$status" -eq 0 ]
    [[ "$output" == *"created Vaultwarden item: github-pat"* ]]
    [[ "$output" == *"\$GITHUB_PAT"* ]]

    # Shim recorded an add call for the right name with the right value.
    grep -q "^add github-pat value=super-secret-value$" "$SHIM_LOG"
}

@test "env var derivation: multi-dash name becomes upper underscores" {
    make_rbw missing ok
    run bash -c "printf 'v\n' | '$NEWSECRET' analogic-gitlab-token"
    [ "$status" -eq 0 ]
    [[ "$output" == *"\$ANALOGIC_GITLAB_TOKEN"* ]]
}

# ---- rbw add failure -------------------------------------------------------

@test "rbw add failure propagates exit 2" {
    make_rbw missing fail
    run bash -c "printf 'v\n' | '$NEWSECRET' doomed-item"
    [ "$status" -eq 2 ]
    [[ "$output" == *"rbw add failed"* ]]
}
