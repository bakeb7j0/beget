#!/usr/bin/env bash
# tests/e2e/e2e-06-template-change-isolation.sh -- E2E-06.
#
# Requirement: R-08, R-19 -- mutating a single template and re-rendering
# only affects that template's output, not others.

set -uo pipefail
REPO="${REPO:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"
# shellcheck source=/dev/null
source "$REPO/tests/e2e/_lib.sh"

run_test() (
    with_mock_rbw ok
    cd "$REPO" || return 1

    local gitconfig_tpl="$REPO/dot_gitconfig.tmpl"
    local aws_tpl="$REPO/private_dot_aws/credentials.tmpl"

    if [[ ! -f "$gitconfig_tpl" || ! -f "$aws_tpl" ]]; then
        _assert_fail "required templates missing"
        return 1
    fi

    local before_aws before_git after_git after_aws
    before_aws="$(chezmoi execute-template --source "$REPO" <"$aws_tpl")" || return 1

    # Work on a copy of the gitconfig template under TEST_WORKDIR
    # so the repo stays clean.
    local tmp_tpl="$TEST_WORKDIR/dot_gitconfig.tmpl"
    cp "$gitconfig_tpl" "$tmp_tpl" || return 1
    printf '\n# e2e sentinel %s\n' "$(date +%s)" >>"$tmp_tpl"

    before_git="$(chezmoi execute-template --source "$REPO" <"$gitconfig_tpl")" || return 1
    after_git="$(chezmoi execute-template --source "$REPO" <"$tmp_tpl")" || return 1
    after_aws="$(chezmoi execute-template --source "$REPO" <"$aws_tpl")" || return 1

    assert_eq "$before_aws" "$after_aws" "AWS template unaffected by git tpl change" || return 1
    assert_ne "$before_git" "$after_git" "git tpl change actually rendered differently" || return 1
)

start=$(date +%s)
failure=""
if ! run_test; then
    failure="assertions failed -- see stderr above"
fi

dur=$(($(date +%s) - start))
if [[ -z "$failure" ]]; then
    echo "E2E-06 PASS"
    emit_junit pass "$dur"
    exit 0
fi
echo "E2E-06 FAIL: $failure" >&2
emit_junit fail "$dur" "$failure"
exit 1
