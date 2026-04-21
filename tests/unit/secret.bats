#!/usr/bin/env bats
# tests/unit/secret.bats — consolidated coverage for the secret surface.
#
# Traceability:
#   IT-04 — secret() (R-13)
#   IT-05 — secret_get() (R-14)
#   IT-06 — _secret_file_from_var name conversion (R-15)
#   IT-07 — newsecret helper (covered in tests/unit/newsecret.bats; this
#           file includes a smoke test that the helper is present and
#           executable so the umbrella suite stays self-contained).
#
# Strategy: source dot_bashrc.d/executable_50-wrappers.sh, use mock_rbw
# from tests/helpers/mocks.sh so rbw calls are deterministic and hermetic.
# Every test uses BEGET_WARN to capture warnings rather than stderr.

setup() {
    REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
    # shellcheck source=/dev/null
    source "$REPO_ROOT/tests/helpers/mocks.sh"

    WRAPPERS_SH="$REPO_ROOT/dot_bashrc.d/executable_50-wrappers.sh"
    NEWSECRET="$REPO_ROOT/dot_local/bin/executable_newsecret"

    export BEGET_WARN="$BATS_TEST_TMPDIR/warnings.log"
    : >"$BEGET_WARN"

    # shellcheck source=/dev/null
    source "$WRAPPERS_SH"
}

# ---- IT-06: name conversion (R-15) -----------------------------------------

@test "IT-06 positive: GITHUB_PAT -> github-pat" {
    run _secret_file_from_var GITHUB_PAT
    [ "$status" -eq 0 ]
    [ "$output" = "github-pat" ]
}

@test "IT-06 positive: multi-component name lowercases and dashes" {
    run _secret_file_from_var ANALOGIC_GITLAB_TOKEN
    [ "$status" -eq 0 ]
    [ "$output" = "analogic-gitlab-token" ]
}

@test "IT-06 negative: empty input fails" {
    run _secret_file_from_var ""
    [ "$status" -ne 0 ]
}

# ---- IT-04: secret() lazy materialization (R-13) ---------------------------

@test "IT-04 positive: materializes from rbw when VAR is empty" {
    mock_rbw ok "pat-xyz"
    unset GITHUB_PAT
    secret GITHUB_PAT
    [ "$GITHUB_PAT" = "pat-xyz" ]
}

@test "IT-04 positive: idempotent when VAR already set (R-13)" {
    # Even a broken rbw must not be invoked when VAR is populated.
    mock_rbw missing
    export GITHUB_PAT="preexisting"
    run secret GITHUB_PAT
    [ "$status" -eq 0 ]
    [ "$GITHUB_PAT" = "preexisting" ]
    [ ! -s "$BEGET_WARN" ]
}

@test "IT-04 negative: missing rbw item -> return 1 + warning" {
    mock_rbw missing
    unset GITHUB_PAT
    run secret GITHUB_PAT
    [ "$status" -eq 1 ]
    grep -q 'rbw get' "$BEGET_WARN"
}

@test "IT-04 negative: rbw locked -> return 1" {
    mock_rbw locked
    unset GITHUB_PAT
    run secret GITHUB_PAT
    [ "$status" -eq 1 ]
}

@test "IT-04 negative: missing VAR arg -> usage error" {
    run secret
    [ "$status" -eq 1 ]
    grep -q 'usage' "$BEGET_WARN"
}

# ---- IT-05: secret_get() prints without mutating env (R-14) ----------------

@test "IT-05 positive: prints value on stdout" {
    mock_rbw ok "hello"
    run secret_get any-item
    [ "$status" -eq 0 ]
    [ "$output" = "hello" ]
}

@test "IT-05 positive: does not mutate env (R-14)" {
    mock_rbw ok "hello"
    unset GITHUB_PAT
    out="$(secret_get github-pat)"
    [ "$out" = "hello" ]
    [ -z "${GITHUB_PAT:-}" ]
}

@test "IT-05 negative: missing item -> return 1" {
    mock_rbw missing
    run secret_get nope
    [ "$status" -eq 1 ]
}

@test "IT-05 negative: missing item arg -> usage error" {
    run secret_get
    [ "$status" -eq 1 ]
    grep -q 'usage' "$BEGET_WARN"
}

# ---- IT-07 smoke: newsecret helper is present and executable ---------------
# Full behavioral coverage lives in tests/unit/newsecret.bats; this smoke
# test ensures the umbrella suite fails loudly if the helper disappears.

@test "IT-07 smoke: newsecret helper exists and is executable" {
    [ -x "$NEWSECRET" ]
}
