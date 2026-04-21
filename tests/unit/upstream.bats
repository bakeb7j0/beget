#!/usr/bin/env bats
# tests/unit/upstream.bats — unit tests for .chezmoiexternal.toml and
# run_onchange_after_90-upstream-install.sh.tmpl.

# The script under test writes progress/errors to STDERR; we use
# `run --separate-stderr` to capture them into $stderr independently
# of any accidental stdout chatter. That flag requires bats ≥1.5.
bats_require_minimum_version 1.5.0

setup() {
    REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
    EXT_TOML="$REPO_ROOT/.chezmoiexternal.toml"
    # Script now lives as .sh.tmpl so chezmoi evaluates the
    # {{ include ".chezmoiexternal.toml" | sha256sum }} re-trigger hash.
    # For bats we run it as a plain bash script — the `{{ ... }}` hash
    # lives inside a comment line that bash ignores.
    SCRIPT="$REPO_ROOT/run_onchange_after_90-upstream-install.sh.tmpl"

    export BEGET_UPSTREAM_BASE="$BATS_TEST_TMPDIR/share"
    mkdir -p "$BEGET_UPSTREAM_BASE"
}

# --- .chezmoiexternal.toml content ------------------------------------------

@test "toml: contains all 5 upstream project sections" {
    [ -r "$EXT_TOML" ]
    grep -q '\[".local/share/claudecode-workflow"\]' "$EXT_TOML"
    grep -q '\[".local/share/tuneviz"\]' "$EXT_TOML"
    grep -q '\[".local/share/gitlab-settings-automation"\]' "$EXT_TOML"
    grep -q '\[".local/share/release-mgr"\]' "$EXT_TOML"
    grep -q '\[".local/share/claude-code-switch"\]' "$EXT_TOML"
}

@test "toml: every section declares type=git-repo and refreshPeriod=168h" {
    local n_type n_refresh n_sections
    n_sections=$(grep -c '^\[".local/share/' "$EXT_TOML")
    n_type=$(grep -c 'type = "git-repo"' "$EXT_TOML")
    # Anchor on leading spaces (the table fields are indented, comment
    # mentions of the same literal start with `#`).
    n_refresh=$(grep -cE '^    refreshPeriod = "168h"' "$EXT_TOML")
    [ "$n_sections" = "5" ]
    [ "$n_type" = "5" ]
    [ "$n_refresh" = "5" ]
}

@test "toml: github repos use github.com/bakeb7j0/ namespace" {
    # 3 github projects
    local n
    n=$(grep -c 'url = "https://github.com/bakeb7j0/' "$EXT_TOML")
    [ "$n" = "3" ]
}

@test "toml: gitlab repos use analogicdev/internal/tools namespace" {
    local n
    n=$(grep -c 'url = "https://gitlab.com/analogicdev/internal/tools/' "$EXT_TOML")
    [ "$n" = "2" ]
}

# --- run_onchange_after_90-upstream-install.sh behaviour --------------------

@test "script: skips when BEGET_UPSTREAM_SKIP=1" {
    # Script logs to stderr; use --separate-stderr so $stderr is assertable.
    BEGET_UPSTREAM_SKIP=1 run --separate-stderr bash "$SCRIPT"
    [ "$status" -eq 0 ]
    [[ "$stderr" == *"skipping all"* ]]
}

@test "script: logs and continues when repo dir absent" {
    # Empty BEGET_UPSTREAM_BASE → no project dirs → 5 'not yet cloned' logs.
    run --separate-stderr bash "$SCRIPT"
    [ "$status" -eq 0 ]
    local n
    n=$(printf '%s\n' "$stderr" | grep -c 'not yet cloned' || true)
    [ "${n:-0}" = "5" ]
}

@test "script: logs and continues when install.sh absent" {
    # Create all 5 dirs but no install.sh in any.
    for p in claudecode-workflow tuneviz gitlab-settings-automation \
             release-mgr claude-code-switch; do
        mkdir -p "$BEGET_UPSTREAM_BASE/$p"
    done
    run --separate-stderr bash "$SCRIPT"
    [ "$status" -eq 0 ]
    local n
    n=$(printf '%s\n' "$stderr" | grep -c 'no install.sh' || true)
    [ "${n:-0}" = "5" ]
    [[ "$stderr" == *"follow-up"* ]]
}

@test "script: executes install.sh when present and executable" {
    # Give tuneviz an install.sh that touches a sentinel, leave others bare.
    mkdir -p "$BEGET_UPSTREAM_BASE/tuneviz"
    cat > "$BEGET_UPSTREAM_BASE/tuneviz/install.sh" <<EOF
#!/usr/bin/env bash
touch "$BATS_TEST_TMPDIR/tuneviz.ran"
EOF
    chmod +x "$BEGET_UPSTREAM_BASE/tuneviz/install.sh"
    # Create the other dirs without install.sh.
    for p in claudecode-workflow gitlab-settings-automation \
             release-mgr claude-code-switch; do
        mkdir -p "$BEGET_UPSTREAM_BASE/$p"
    done

    run --separate-stderr bash "$SCRIPT"
    [ "$status" -eq 0 ]
    [ -f "$BATS_TEST_TMPDIR/tuneviz.ran" ]
}

@test "script: failing installer flags failure but continues" {
    # tuneviz installer fails; others are absent. Script must exit non-zero
    # but still log 'not yet cloned' or 'no install.sh' for the rest.
    mkdir -p "$BEGET_UPSTREAM_BASE/tuneviz"
    cat > "$BEGET_UPSTREAM_BASE/tuneviz/install.sh" <<'EOF'
#!/usr/bin/env bash
echo "boom" >&2
exit 7
EOF
    chmod +x "$BEGET_UPSTREAM_BASE/tuneviz/install.sh"
    # Give a second installer that succeeds to prove iteration continues.
    mkdir -p "$BEGET_UPSTREAM_BASE/release-mgr"
    cat > "$BEGET_UPSTREAM_BASE/release-mgr/install.sh" <<EOF
#!/usr/bin/env bash
touch "$BATS_TEST_TMPDIR/release-mgr.ran"
EOF
    chmod +x "$BEGET_UPSTREAM_BASE/release-mgr/install.sh"

    run --separate-stderr bash "$SCRIPT"
    [ "$status" -ne 0 ]
    [ -f "$BATS_TEST_TMPDIR/release-mgr.ran" ]
    [[ "$stderr" == *"tuneviz installer failed"* ]]
    [[ "$stderr" == *"1 installer(s) failed"* ]]
}

@test "script: dry-run lists installers without exec" {
    mkdir -p "$BEGET_UPSTREAM_BASE/tuneviz"
    cat > "$BEGET_UPSTREAM_BASE/tuneviz/install.sh" <<EOF
#!/usr/bin/env bash
touch "$BATS_TEST_TMPDIR/should-not-exist"
EOF
    chmod +x "$BEGET_UPSTREAM_BASE/tuneviz/install.sh"
    BEGET_UPSTREAM_DRY_RUN=1 run --separate-stderr bash "$SCRIPT"
    [ "$status" -eq 0 ]
    [[ "$stderr" == *"DRY-RUN would exec"* ]]
    [ ! -f "$BATS_TEST_TMPDIR/should-not-exist" ]
}
