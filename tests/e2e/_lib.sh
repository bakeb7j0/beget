#!/usr/bin/env bash
# tests/e2e/_lib.sh -- shared helpers for E2E tests.
#
# NOTE: Tests source this under `set -uo pipefail` (no -e). Each test
# wraps its body in `run_test() { ... }` and checks the return value
# of run_test. Every assertion short-circuits via `|| return 1` so a
# failure actually short-circuits the test body.
#
# Provides:
#   assert_eq      -- fail the test when two values differ
#   assert_match   -- fail when a string doesn't match a regex
#   emit_junit     -- write a single-testcase JUnit XML file
#   with_mock_rbw  -- install a mock rbw on PATH (ok|missing modes)
#
# Tests are intended to run both inside a container (invoked by
# scripts/ci/run-e2e.sh) and directly from a developer workstation for
# debugging. They must be hermetic: no persistent state outside the
# TEST_WORKDIR that the runner provides.

set -uo pipefail

# TEST_WORKDIR and TEST_NAME are provided by the invoker. Fall back to
# temp-directory defaults for direct invocation.
TEST_WORKDIR="${TEST_WORKDIR:-$(mktemp -d)}"
TEST_NAME="${TEST_NAME:-$(basename "${BASH_SOURCE[1]:-$0}" .sh)}"
TEST_RESULTS_DIR="${TEST_RESULTS_DIR:-tests/results}"
mkdir -p "$TEST_RESULTS_DIR"

_assert_fail() {
    printf '  ASSERT FAILED: %s\n' "$*" >&2
    return 1
}

assert_eq() {
    local actual="$1" expected="$2" msg="${3:-}"
    if [[ "$actual" != "$expected" ]]; then
        _assert_fail "${msg:-expected}='$expected' got='$actual'"
        return 1
    fi
}

assert_ne() {
    local actual="$1" unexpected="$2" msg="${3:-}"
    if [[ "$actual" == "$unexpected" ]]; then
        _assert_fail "${msg:-value}='$actual' matched forbidden '$unexpected'"
        return 1
    fi
}

assert_match() {
    local haystack="$1" regex="$2" msg="${3:-}"
    if [[ ! "$haystack" =~ $regex ]]; then
        _assert_fail "${msg:-regex mismatch}: needle='$regex' hay='${haystack:0:200}'"
        return 1
    fi
}

# emit_junit <status> <duration_sec> [failure_message]
# status: pass | fail
emit_junit() {
    local status="$1" duration="$2" failure="${3:-}"
    local out="$TEST_RESULTS_DIR/${TEST_NAME}.xml"
    local ts cases
    ts="$(date -u +%Y-%m-%dT%H:%M:%S)"

    if [[ "$status" == "pass" ]]; then
        cases='<testcase classname="beget.e2e" name="'"$TEST_NAME"'" time="'"$duration"'"/>'
    else
        # XML-escape the failure message for the attribute; CDATA body
        # carries the raw text (tests control content, so `]]>` isn't
        # a realistic concern). Backslash-escape `&` in replacements --
        # bash parameter expansion treats unescaped `&` as "the matched
        # text", so `${x//</&lt;}` yields `<lt;` not `&lt;`.
        local escaped="${failure//&/\&amp;}"
        escaped="${escaped//</\&lt;}"
        escaped="${escaped//>/\&gt;}"
        escaped="${escaped//\"/\&quot;}"
        cases='<testcase classname="beget.e2e" name="'"$TEST_NAME"'" time="'"$duration"'"><failure message="'"$escaped"'"><![CDATA['"$failure"']]></failure></testcase>'
    fi

    cat >"$out" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<testsuites>
  <testsuite name="$TEST_NAME" tests="1" failures="$([[ "$status" == "fail" ]] && echo 1 || echo 0)" errors="0" skipped="0" timestamp="$ts">
    $cases
  </testsuite>
</testsuites>
EOF
}

# with_mock_rbw <mode>
# mode: ok (returns valid JSON for any get) | missing (every get exits 1)
with_mock_rbw() {
    local mode="${1:-ok}"
    local shim_dir="$TEST_WORKDIR/rbw-shim"
    mkdir -p "$shim_dir"
    cat >"$shim_dir/rbw" <<'EOF'
#!/usr/bin/env bash
case "${1:-}" in
    --version) echo "rbw 1.14.0 (e2e mock)"; exit 0 ;;
    login) exit 0 ;;
    unlock) exit 0 ;;
    get)
        shift
        while [[ $# -gt 0 ]]; do
            case "$1" in
                --raw|--field|--full) shift ;;
                *) break ;;
            esac
        done
        item="${1:-}"
        if [[ "${E2E_RBW_MODE:-ok}" = "missing" ]]; then
            echo "rbw: no item '$item'" >&2
            exit 1
        fi
        case "$item" in
            ssh-id-*)
                printf '{"name":"%s","fields":[{"name":"privateKey","value":"-----BEGIN OPENSSH PRIVATE KEY-----\\nAAAAMOCK\\n-----END OPENSSH PRIVATE KEY-----\\n"},{"name":"publicKey","value":"ssh-ed25519 AAAAMOCK %s"}]}\n' "$item" "$item"
                ;;
            aws-*)
                printf '{"name":"%s","data":{"username":"AKIAMOCK","password":"SECRETMOCK/AKIAMOCK"},"fields":[]}\n' "$item"
                ;;
            *)
                printf 'mock-value-for-%s\n' "$item"
                ;;
        esac
        exit 0
        ;;
    *) exit 0 ;;
esac
EOF
    chmod +x "$shim_dir/rbw"
    export E2E_RBW_MODE="$mode"
    export PATH="$shim_dir:$PATH"
}

# Invoke install.sh with preflight-only semantics: source it with
# BEGET_INSTALL_SOURCED=1 so main() does not execute, then call
# individual functions directly. Callers get access to parse_flags,
# preflight, install_prereqs, etc.
source_install() {
    local repo="${1:?repo path required}"
    export BEGET_INSTALL_SOURCED=1
    # Suppress the /dev/tty stdin reparent block at the top of install.sh.
    # The reparent logs a harmless "No such device or address" on stderr in
    # sandboxes where /dev/tty exists as a char device but cannot be
    # opened, which pollutes test output even though the `|| true` keeps
    # bash running.
    export BEGET_SKIP_TTY_REPARENT=1
    # install.sh defers sourcing lib/platform.sh until main(); since
    # we skip main(), bring platform.sh in directly so preflight /
    # install_prereqs have source_os_release + friends available.
    # shellcheck source=/dev/null
    source "$repo/lib/platform.sh"
    # shellcheck source=/dev/null
    source "$repo/install.sh"
}
