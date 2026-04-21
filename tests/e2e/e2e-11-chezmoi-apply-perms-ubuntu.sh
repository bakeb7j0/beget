#!/usr/bin/env bash
# tests/e2e/e2e-11-chezmoi-apply-perms-ubuntu.sh -- E2E-11.
#
# Requirements: R-17 (SSH keys materialized to ~/.ssh/ with 0600) and
# R-18 (~/.aws/credentials materialized with 0600) from
# docs/beget-devspec.md.
#
# Gap this closes: existing E2E-04 / E2E-06 / IT-03 exercise
# `chezmoi execute-template` (render-only) against the mock rbw
# shim, which proves templates compile but never proves the effectful
# outcome -- file existence at the destination path, mode bits, and
# idempotency. R-17/R-18 explicitly require 0600 permissions, a
# property no template-render test can verify.
#
# Strategy: run `chezmoi apply` (not execute-template) against a
# fresh $HOME (mktemp -d), with mock rbw on PATH and --exclude=scripts
# so we skip all the run_onchange_* package/repo work and focus
# tightly on files-to-disk. The distro-ubuntu suffix on the filename
# restricts this to the ubuntu24 e2e job because apply at this layer
# is OS-independent -- Rocky runtime would duplicate coverage for
# zero marginal signal.
#
# Dispatcher note: scripts/ci/run-e2e.sh's `*-chezmoi-apply-*` clause
# routes us to `--user 1000:1000 -e HOME=/home/beget`. That preset
# HOME is intentionally shadowed by our mktemp override inside the
# test so apply lands in a scratch dir, never /home/beget/.ssh.

set -uo pipefail
REPO="${REPO:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"
# shellcheck source=/dev/null
source "$REPO/tests/e2e/_lib.sh"

# Catalog-driven identity and profile lists. Parsing docs/catalog-*.md
# directly keeps the test self-updating as catalogs evolve; a new row
# in either catalog must land somewhere in the fleet, and this test
# will automatically verify the new materialization.
ssh_identities() {
    awk -F'|' '/^\| `id_/ { gsub(/^[[:space:]]*`/, "", $2); gsub(/`[[:space:]]*$/, "", $2); print $2 }' \
        "$REPO/docs/catalog-a-ssh-identities.md"
}

# Catalog B has two tables. The first (rows without a "VW item" column)
# is the high-level list; the second (with `aws-<name>` VW item names)
# is the rendering order. We want profile names from the first table;
# uniquifying guards against the second-table duplication.
aws_profiles() {
    awk -F'|' '/^\| `[a-z]/ { gsub(/^[[:space:]]*`/, "", $2); gsub(/`[[:space:]]*$/, "", $2); print $2 }' \
        "$REPO/docs/catalog-b-aws-profiles.md" | sort -u
}

FAKE_HOME=""
ORIG_HOME="$HOME"

# shellcheck disable=SC2317
cleanup() {
    # Restore HOME before nuking the scratch dir so any post-test code
    # (harness cleanup, shell prompt init) references a valid path rather
    # than the tmpdir we're about to delete.
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
    # Fresh $HOME. mktemp + explicit export shadows the container's
    # `HOME=/home/beget` preset.
    FAKE_HOME="$(mktemp -d -t beget-e2e-11.XXXXXX)"
    export HOME="$FAKE_HOME"

    # Also redirect XDG dirs so chezmoi's config/data writes don't
    # escape the scratch dir. chezmoi looks at XDG_CONFIG_HOME /
    # XDG_DATA_HOME before falling back to ~/.config / ~/.local/share;
    # setting them here keeps every file chezmoi touches under
    # FAKE_HOME.
    export XDG_CONFIG_HOME="$FAKE_HOME/.config"
    export XDG_DATA_HOME="$FAKE_HOME/.local/share"
    mkdir -p "$XDG_CONFIG_HOME" "$XDG_DATA_HOME"

    with_mock_rbw ok

    # Apply. --source points at the working-tree checkout, so we
    # exercise the source state currently under review rather than a
    # cloned copy. --exclude=scripts suppresses the run_onchange_*
    # dotfiles, which would otherwise try to register apt/dnf repos,
    # install packages, enable sysctls, etc. The apply-mode file
    # materialization (mode bits, private_ prefix, symlinks) is what
    # R-17/R-18 actually require, and that's what we want to measure.
    if ! chezmoi apply --source "$REPO" --exclude=scripts 2>"$FAKE_HOME/apply.stderr"; then
        echo "--- chezmoi apply stderr ---" >&2
        cat "$FAKE_HOME/apply.stderr" >&2
        _assert_fail "chezmoi apply exited non-zero"
        return 1
    fi

    # --- R-17: SSH identities materialized with 0600 ---
    local expected_ssh ssh_found=0
    while IFS= read -r expected_ssh; do
        [[ -z "$expected_ssh" ]] && continue
        ssh_found=$((ssh_found + 1))
        assert_mode_0600 "$HOME/.ssh/$expected_ssh" "SSH $expected_ssh" || return 1
        # Mock shim emits `AAAAMOCK` in every ssh-* privateKey value.
        # Grepping for that marker proves the template actually pulled
        # from rbw rather than falling through to an empty/default.
        if ! grep -q "AAAAMOCK" "$HOME/.ssh/$expected_ssh"; then
            _assert_fail "SSH $expected_ssh missing AAAAMOCK marker — template did not consume rbw output"
            return 1
        fi
    done < <(ssh_identities)

    if ((ssh_found == 0)); then
        _assert_fail "catalog-a parser found zero SSH identities — check docs/catalog-a-ssh-identities.md"
        return 1
    fi

    # --- R-18: ~/.aws/credentials materialized with 0600 ---
    assert_mode_0600 "$HOME/.aws/credentials" "AWS credentials" || return 1

    # Every catalog-B profile must appear as a [profile] section AND
    # every aws_access_key_id line must carry the AKIAMOCK marker
    # (proving rbw was consulted for each profile, not just one).
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
    # Anchor the grep to `aws_access_key_id = AKIAMOCK` specifically.
    # A loose `grep -c 'AKIAMOCK'` would double-count because the mock
    # also embeds AKIAMOCK in the password field (SECRETMOCK/AKIAMOCK),
    # and the resulting count (2*profile_count) would satisfy a `<`
    # comparison trivially — a silent-pass hazard. One access-key-id
    # line per profile is the exact invariant the template produces.
    akia_lines="$(grep -c '^aws_access_key_id = AKIAMOCK' "$HOME/.aws/credentials" || true)"
    if ((akia_lines != profile_count)); then
        _assert_fail "AWS credentials: $akia_lines AKIAMOCK access-key-id lines for $profile_count profiles — expected exact equality"
        return 1
    fi

    # --- R-07 at the apply layer: second apply is a no-op ---
    # Record mtimes of every materialized secret file, re-apply, and
    # assert nothing moved. chezmoi's apply-if-changed logic depends
    # on content hash equality across runs; mock rbw is deterministic
    # so a second apply SHOULD detect no-change and write nothing.
    local -A mtimes_before
    local rel_path abs_path
    while IFS= read -r expected_ssh; do
        [[ -z "$expected_ssh" ]] && continue
        rel_path=".ssh/$expected_ssh"
        abs_path="$HOME/$rel_path"
        mtimes_before["$rel_path"]="$(stat -c %Y "$abs_path")"
    done < <(ssh_identities)
    mtimes_before[".aws/credentials"]="$(stat -c %Y "$HOME/.aws/credentials")"

    # Sleep a second so any accidental rewrite would be detectable at
    # whole-second resolution. Overkill on most filesystems but cheap
    # insurance against coarse-grained timestamp support.
    sleep 1

    if ! chezmoi apply --source "$REPO" --exclude=scripts 2>"$FAKE_HOME/apply2.stderr"; then
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
    echo "E2E-11 PASS"
    emit_junit pass "$dur"
    exit 0
fi
echo "E2E-11 FAIL: $failure" >&2
emit_junit fail "$dur" "$failure"
exit 1
