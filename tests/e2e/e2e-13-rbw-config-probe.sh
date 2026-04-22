#!/usr/bin/env bash
# tests/e2e/e2e-13-rbw-config-probe.sh -- E2E-13.
#
# Requirement: Issue #98 Bug A — rbw 1.15.0 has no `status` subcommand.
# rbw_prompt_if_needed() must probe for ~/.config/rbw/config.json rather
# than invoking a nonexistent `rbw status`. This test stands in for the
# "interactive install with scripted rbw mock" E2E envisioned in the
# plan: running a fully-interactive bootstrap inside docker would require
# pty allocation the runner doesn't provide. Instead, we exercise the
# exact seam (rbw_prompt_if_needed) against the real repo's install.sh
# under two realistic states:
#
#   1. config.json exists -> rbw_prompt_if_needed short-circuits, does
#      NOT invoke rbw (the mock would fail loudly if it did).
#   2. config.json absent + DRY_RUN=1 -> rbw_prompt_if_needed reports it
#      would run `rbw login` (not `rbw status`).
#
# Pair with E2E-14 for the --skip-secrets non-interactive complement.

set -uo pipefail
REPO="${REPO:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"
# shellcheck source=/dev/null
source "$REPO/tests/e2e/_lib.sh"

install_failing_rbw_stub() {
    # Stub rbw that exits non-zero on ANY invocation. rbw_prompt_if_needed
    # must never invoke it when config.json exists.
    local shim_dir="$1"
    mkdir -p "$shim_dir"
    cat >"$shim_dir/rbw" <<'EOF'
#!/usr/bin/env bash
echo "FAIL: rbw should not have been invoked (args: $*)" >&2
exit 77
EOF
    chmod +x "$shim_dir/rbw"
}

run_test() {
    source_install "$REPO" || return 1

    # --- Case 1: config.json exists -> no rbw invocation -------------------
    local tmp_home
    tmp_home="$(mktemp -d)"
    mkdir -p "$tmp_home/.config/rbw"
    printf '{"email":"e2e@example.com"}\n' >"$tmp_home/.config/rbw/config.json"

    local stub_dir
    stub_dir="$(mktemp -d)"
    install_failing_rbw_stub "$stub_dir"

    parse_flags || return 1 # defaults: SKIP_SECRETS=0, DRY_RUN=0

    local out rc=0
    out="$(HOME="$tmp_home" PATH="$stub_dir:$PATH" rbw_prompt_if_needed 2>&1)" || rc=$?
    if [[ $rc -ne 0 ]]; then
        _assert_fail "rbw_prompt_if_needed exited $rc with existing config: $out"
        rm -rf "$tmp_home" "$stub_dir"
        return 1
    fi
    assert_match "$out" "rbw already configured" "config.json probe succeeded" ||
        {
            rm -rf "$tmp_home" "$stub_dir"
            return 1
        }
    if [[ "$out" == *"FAIL: rbw should not have been invoked"* ]]; then
        _assert_fail "rbw was invoked despite config.json existing: $out"
        rm -rf "$tmp_home" "$stub_dir"
        return 1
    fi
    rm -rf "$tmp_home" "$stub_dir"

    # --- Case 2: config.json absent + DRY_RUN=1 -> would run `rbw login`----
    tmp_home="$(mktemp -d)"
    # No ~/.config/rbw directory at all.
    stub_dir="$(mktemp -d)"
    install_failing_rbw_stub "$stub_dir"

    parse_flags --dry-run || return 1

    out="$(HOME="$tmp_home" PATH="$stub_dir:$PATH" rbw_prompt_if_needed 2>&1)" || rc=$?
    if [[ $rc -ne 0 ]]; then
        _assert_fail "rbw_prompt_if_needed dry-run exited $rc: $out"
        rm -rf "$tmp_home" "$stub_dir"
        return 1
    fi
    assert_match "$out" "would prompt: rbw login" "dry-run would run rbw login" ||
        {
            rm -rf "$tmp_home" "$stub_dir"
            return 1
        }

    # --- Case 3: install.sh must not reference `rbw status` anywhere -------
    if grep -qE '\brbw[[:space:]]+status\b' "$REPO/install.sh"; then
        _assert_fail "install.sh still references 'rbw status' (Bug A regressed)"
        rm -rf "$tmp_home" "$stub_dir"
        return 1
    fi

    rm -rf "$tmp_home" "$stub_dir"
}

start=$(date +%s)
failure=""
if ! run_test; then
    failure="assertions failed -- see stderr above"
fi

dur=$(($(date +%s) - start))
if [[ -z "$failure" ]]; then
    echo "E2E-13 PASS"
    emit_junit pass "$dur"
    exit 0
fi
echo "E2E-13 FAIL: $failure" >&2
emit_junit fail "$dur" "$failure"
exit 1
