#!/usr/bin/env bash
# tests/e2e/e2e-04-mock-rbw-materialize.sh -- E2E-04.
#
# Requirement: R-17, R-18 -- SSH / AWS credentials materialize from
# mocked rbw via chezmoi execute-template. We render the actual
# templates (private_dot_ssh/private_id_ed25519.tmpl, private_dot_aws/
# credentials.tmpl) against our mock rbw and assert the rendered
# content has the mock markers.

set -uo pipefail
REPO="${REPO:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"
# shellcheck source=/dev/null
source "$REPO/tests/e2e/_lib.sh"

run_test() (
    with_mock_rbw ok
    cd "$REPO" || return 1

    local ssh_tpl="$REPO/private_dot_ssh/private_id_ed25519.tmpl"
    if [[ ! -f "$ssh_tpl" ]]; then
        _assert_fail "SSH template missing: $ssh_tpl"
        return 1
    fi
    local rendered
    rendered="$(chezmoi execute-template --source "$REPO" <"$ssh_tpl")" || return 1
    assert_match "$rendered" "OPENSSH PRIVATE KEY" "SSH key materialized" || return 1
    assert_match "$rendered" "AAAAMOCK" "mock marker present" || return 1

    local aws_tpl="$REPO/private_dot_aws/private_credentials.tmpl"
    if [[ -f "$aws_tpl" ]]; then
        local rendered2
        rendered2="$(chezmoi execute-template --source "$REPO" <"$aws_tpl")" || return 1
        assert_match "$rendered2" "aws_access_key_id = AKIAMOCK" "AWS key materialized" || return 1
    fi
)

start=$(date +%s)
failure=""
if ! run_test; then
    failure="assertions failed -- see stderr above"
fi

dur=$(($(date +%s) - start))
if [[ -z "$failure" ]]; then
    echo "E2E-04 PASS"
    emit_junit pass "$dur"
    exit 0
fi
echo "E2E-04 FAIL: $failure" >&2
emit_junit fail "$dur" "$failure"
exit 1
