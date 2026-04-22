#!/usr/bin/env bash
# tests/e2e/e2e-14-skip-secrets-chezmoi-render.sh -- E2E-14.
#
# Requirement: Issue #98 Bug C — when --skip-secrets is passed, the
# skip_secrets data var must reach chezmoi so rbw-calling templates
# render empty rather than trying to fetch secrets. This test drives
# the fix end-to-end against the real repo templates:
#
#   1. Run write_chezmoi_config under --skip-secrets -> ${HOME}/.config/
#      chezmoi/chezmoi.toml must contain `skip_secrets = true`.
#   2. Render the rbw-using templates (AWS credentials, every SSH key)
#      via `chezmoi execute-template` with a failing-rbw stub on PATH.
#      Templates MUST NOT invoke rbw; output must be empty (or contain
#      only the non-secret comment header, in the AWS case).
#
# Pairs with E2E-13 (rbw_prompt_if_needed probe path).

set -uo pipefail
REPO="${REPO:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"
# shellcheck source=/dev/null
source "$REPO/tests/e2e/_lib.sh"

install_failing_rbw_stub() {
    local shim_dir="$1"
    mkdir -p "$shim_dir"
    cat >"$shim_dir/rbw" <<'EOF'
#!/usr/bin/env bash
echo "FAIL: rbw invoked under --skip-secrets (args: $*)" >&2
exit 77
EOF
    chmod +x "$shim_dir/rbw"
}

run_test() {
    source_install "$REPO" || return 1

    # --- Case 1: write_chezmoi_config emits skip_secrets = true ------------
    local tmp_home
    tmp_home="$(mktemp -d)"

    parse_flags --skip-secrets || {
        rm -rf "$tmp_home"
        return 1
    }

    HOME="$tmp_home" write_chezmoi_config || {
        _assert_fail "write_chezmoi_config failed under --skip-secrets"
        rm -rf "$tmp_home"
        return 1
    }

    local cfg="$tmp_home/.config/chezmoi/chezmoi.toml"
    if [[ ! -f "$cfg" ]]; then
        _assert_fail "chezmoi.toml not written: $cfg"
        rm -rf "$tmp_home"
        return 1
    fi
    local cfg_body
    cfg_body="$(cat "$cfg")"
    assert_match "$cfg_body" "skip_secrets = true" "skip_secrets=true in chezmoi.toml" ||
        {
            rm -rf "$tmp_home"
            return 1
        }

    # --- Case 2: templates render empty with skip_secrets=true + failing rbw
    local stub_dir
    stub_dir="$(mktemp -d)"
    install_failing_rbw_stub "$stub_dir"

    # chezmoi execute-template accepts config via --config. We build a
    # minimal config pointing at the same [data] shape install.sh writes.
    local data_cfg="$tmp_home/skip-secrets-data.toml"
    cat >"$data_cfg" <<'TOML'
[data]
    skip_secrets = true
TOML

    # Enumerate every rbw-calling template by grepping the source tree.
    # A static list would drift silently as new secret-bearing templates
    # land; discovering them at test time guarantees every new one is
    # gated by skip_secrets.
    local templates=()
    mapfile -t templates < <(
        grep -rl --include='*.tmpl' '\brbw\b' \
            "$REPO/private_dot_aws" \
            "$REPO/private_dot_ssh" 2>/dev/null |
            sed "s|^$REPO/||" | sort
    )
    if [[ ${#templates[@]} -eq 0 ]]; then
        _assert_fail "no rbw-calling templates discovered under private_dot_{aws,ssh}"
        rm -rf "$tmp_home" "$stub_dir"
        return 1
    fi

    local tpl rendered rc=0
    for tpl in "${templates[@]}"; do
        local full="$REPO/$tpl"
        if [[ ! -f "$full" ]]; then
            _assert_fail "expected template not found: $full"
            rm -rf "$tmp_home" "$stub_dir"
            return 1
        fi

        rc=0
        rendered="$(
            PATH="$stub_dir:$PATH" chezmoi execute-template \
                --config "$data_cfg" \
                --source "$REPO" \
                <"$full" 2>&1
        )" || rc=$?

        if [[ $rc -ne 0 ]]; then
            _assert_fail "$tpl: chezmoi execute-template failed (rc=$rc): $rendered"
            rm -rf "$tmp_home" "$stub_dir"
            return 1
        fi

        if [[ "$rendered" == *"FAIL: rbw invoked"* ]]; then
            _assert_fail "$tpl: rbw was invoked despite skip_secrets=true"
            rm -rf "$tmp_home" "$stub_dir"
            return 1
        fi

        # SSH templates collapse to empty under skip_secrets. The AWS
        # credentials template keeps its comment header but MUST NOT
        # contain an aws_access_key_id line (that half sits behind the
        # gate).
        case "$tpl" in
            *private_credentials.tmpl)
                if [[ "$rendered" == *"aws_access_key_id"* ]]; then
                    _assert_fail "AWS credentials: key body rendered under skip_secrets=true"
                    rm -rf "$tmp_home" "$stub_dir"
                    return 1
                fi
                ;;
            *)
                # SSH templates: strip whitespace; must be empty.
                local stripped="${rendered//[$' \t\r\n']/}"
                if [[ -n "$stripped" ]]; then
                    _assert_fail "$tpl: non-empty render under skip_secrets=true: $rendered"
                    rm -rf "$tmp_home" "$stub_dir"
                    return 1
                fi
                ;;
        esac
    done

    rm -rf "$tmp_home" "$stub_dir"
}

start=$(date +%s)
failure=""
if ! run_test; then
    failure="assertions failed -- see stderr above"
fi

dur=$(($(date +%s) - start))
if [[ -z "$failure" ]]; then
    echo "E2E-14 PASS"
    emit_junit pass "$dur"
    exit 0
fi
echo "E2E-14 FAIL: $failure" >&2
emit_junit fail "$dur" "$failure"
exit 1
