#!/usr/bin/env bash
# tests/e2e/e2e-12-chezmoi-apply-perms-rocky.sh -- E2E-12.
#
# Rocky counterpart to E2E-11. Covers two layers the ubuntu test
# doesn't reach on a dnf host:
#
#   1. R-17/R-18 file materialization (duplicated from E2E-11) — proves
#      `chezmoi apply` honors mode 0600 on SSH keys and AWS credentials
#      on Rocky9 too. Same assertion as E2E-11 but distinct runtime.
#   2. .chezmoiignore.tmpl dispatch — on Rocky, `run_onchange_before_
#      10-apt-repos.sh` MUST be ignored and `..._10-dnf-repos.sh` MUST
#      NOT be ignored. This is the regression guard the #97 dispatch
#      bug would have triggered pre-merge instead of only as a post-
#      merge smoke canary failure.
#
# The dispatch probe renders .chezmoiignore.tmpl directly via
# `chezmoi execute-template` rather than probing /etc/apt/sources.list.d/*
# because the apply runs with --exclude=scripts (keeping the test
# hermetic — no package installs, no sudo), so no script actually
# executes. Rendered-ignore output is exactly the contract between
# chezmoi and the filesystem: whatever the template emits here is
# what chezmoi will skip at apply time.
#
# Dispatcher note: scripts/ci/run-e2e.sh's `*-chezmoi-apply-*` clause
# routes us to `--user 1000:1000 -e HOME=/home/beget` on the rocky9
# image. That HOME is intentionally shadowed by the mktemp override
# inside the test so apply lands in a scratch dir.

set -uo pipefail
REPO="${REPO:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"
# shellcheck source=/dev/null
source "$REPO/tests/e2e/_lib.sh"

ssh_identities() {
    awk -F'|' '/^\| `id_/ { gsub(/^[[:space:]]*`/, "", $2); gsub(/`[[:space:]]*$/, "", $2); print $2 }' \
        "$REPO/docs/catalog-a-ssh-identities.md"
}

aws_profiles() {
    awk -F'|' '/^\| `[a-z]/ { gsub(/^[[:space:]]*`/, "", $2); gsub(/`[[:space:]]*$/, "", $2); print $2 }' \
        "$REPO/docs/catalog-b-aws-profiles.md" | sort -u
}

FAKE_HOME=""
ORIG_HOME="$HOME"

# shellcheck disable=SC2317
cleanup() {
    export HOME="$ORIG_HOME"
    if [[ -n "$FAKE_HOME" && -d "$FAKE_HOME" ]]; then
        rm -rf "$FAKE_HOME"
    fi
}
trap cleanup EXIT

assert_mode_0600() {
    local path="$1" label="$2" mode
    if [[ ! -f "$path" ]]; then
        _assert_fail "$label: file missing at $path"
        return 1
    fi
    mode="$(stat -c %a "$path")"
    if [[ "$mode" != "600" ]]; then
        _assert_fail "$label: mode=$mode expected 600 ($path)"
        return 1
    fi
}

run_test() {
    FAKE_HOME="$(mktemp -d -t beget-e2e-12.XXXXXX)"
    export HOME="$FAKE_HOME"
    export XDG_CONFIG_HOME="$FAKE_HOME/.config"
    export XDG_DATA_HOME="$FAKE_HOME/.local/share"
    mkdir -p "$XDG_CONFIG_HOME" "$XDG_DATA_HOME"

    with_mock_rbw ok

    # --- .chezmoiignore.tmpl dispatch (the #97 regression guard) ---
    # On rocky9, the rendered ignore list MUST include apt-repos.sh
    # (so chezmoi skips it) and MUST NOT include dnf-repos.sh (so
    # chezmoi runs it). Do this BEFORE apply so the assertion still
    # fires even if apply itself errors.
    local ignore_list
    if ! ignore_list="$(chezmoi execute-template <"$REPO/.chezmoiignore.tmpl" 2>"$FAKE_HOME/ignore.stderr")"; then
        echo "--- chezmoi execute-template stderr ---" >&2
        cat "$FAKE_HOME/ignore.stderr" >&2
        _assert_fail "chezmoi execute-template exited non-zero on .chezmoiignore.tmpl"
        return 1
    fi
    if ! grep -Fxq "run_onchange_before_10-apt-repos.sh" <<<"$ignore_list"; then
        echo "--- rendered ignore list ---" >&2
        printf '%s\n' "$ignore_list" >&2
        _assert_fail "dispatch: run_onchange_before_10-apt-repos.sh NOT in ignore list on rocky9 — .chezmoiignore.tmpl did not gate it"
        return 1
    fi
    if grep -Fxq "run_onchange_before_10-dnf-repos.sh" <<<"$ignore_list"; then
        echo "--- rendered ignore list ---" >&2
        printf '%s\n' "$ignore_list" >&2
        _assert_fail "dispatch: run_onchange_before_10-dnf-repos.sh IS in ignore list on rocky9 — .chezmoiignore.tmpl over-filtered"
        return 1
    fi

    # --- R-17/R-18 file materialization ---
    if ! chezmoi apply --source "$REPO" --exclude=scripts,externals 2>"$FAKE_HOME/apply.stderr"; then
        echo "--- chezmoi apply stderr ---" >&2
        cat "$FAKE_HOME/apply.stderr" >&2
        _assert_fail "chezmoi apply exited non-zero"
        return 1
    fi

    local expected_ssh ssh_found=0
    while IFS= read -r expected_ssh; do
        [[ -z "$expected_ssh" ]] && continue
        ssh_found=$((ssh_found + 1))
        assert_mode_0600 "$HOME/.ssh/$expected_ssh" "SSH $expected_ssh" || return 1
        if ! grep -q "AAAAMOCK" "$HOME/.ssh/$expected_ssh"; then
            _assert_fail "SSH $expected_ssh missing AAAAMOCK marker — template did not consume rbw output"
            return 1
        fi
    done < <(ssh_identities)

    if ((ssh_found == 0)); then
        _assert_fail "catalog-a parser found zero SSH identities — check docs/catalog-a-ssh-identities.md"
        return 1
    fi

    assert_mode_0600 "$HOME/.aws/credentials" "AWS credentials" || return 1

    local expected_profile profile_count=0 akia_lines
    while IFS= read -r expected_profile; do
        [[ -z "$expected_profile" ]] && continue
        profile_count=$((profile_count + 1))
        if ! grep -Fq "[$expected_profile]" "$HOME/.aws/credentials"; then
            _assert_fail "AWS credentials: section [$expected_profile] missing"
            return 1
        fi
    done < <(aws_profiles)
    if ((profile_count == 0)); then
        _assert_fail "catalog-b parser found zero profiles — check docs/catalog-b-aws-profiles.md"
        return 1
    fi
    akia_lines="$(grep -c '^aws_access_key_id = AKIAMOCK' "$HOME/.aws/credentials" || true)"
    if ((akia_lines != profile_count)); then
        _assert_fail "AWS credentials: $akia_lines AKIAMOCK access-key-id lines for $profile_count profiles — expected exact equality"
        return 1
    fi

    # --- R-07: second apply is a no-op ---
    local -A mtimes_before
    local rel_path abs_path
    while IFS= read -r expected_ssh; do
        [[ -z "$expected_ssh" ]] && continue
        rel_path=".ssh/$expected_ssh"
        abs_path="$HOME/$rel_path"
        mtimes_before["$rel_path"]="$(stat -c %Y "$abs_path")"
    done < <(ssh_identities)
    mtimes_before[".aws/credentials"]="$(stat -c %Y "$HOME/.aws/credentials")"

    sleep 1

    if ! chezmoi apply --source "$REPO" --exclude=scripts,externals 2>"$FAKE_HOME/apply2.stderr"; then
        echo "--- second apply stderr ---" >&2
        cat "$FAKE_HOME/apply2.stderr" >&2
        _assert_fail "second chezmoi apply exited non-zero (idempotency regression)"
        return 1
    fi

    local mtime_after
    for rel_path in "${!mtimes_before[@]}"; do
        mtime_after="$(stat -c %Y "$HOME/$rel_path")"
        if [[ "$mtime_after" != "${mtimes_before[$rel_path]}" ]]; then
            _assert_fail "idempotency: $rel_path mtime changed ${mtimes_before[$rel_path]} -> $mtime_after on second apply"
            return 1
        fi
    done
}

start=$(date +%s)
failure=""
if ! run_test; then
    failure="assertions failed -- see stderr above"
fi

dur=$(($(date +%s) - start))
if [[ -z "$failure" ]]; then
    echo "E2E-12 PASS"
    emit_junit pass "$dur"
    exit 0
fi
echo "E2E-12 FAIL: $failure" >&2
emit_junit fail "$dur" "$failure"
exit 1
