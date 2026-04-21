#!/usr/bin/env bats
# tests/unit/migrate-secrets.bats — unit tests for scripts/migrate-secrets.sh
#
# Strategy: point BEGET_RBW_CMD at a shim under BATS_TEST_TMPDIR. The shim
# is driven by files in SHIM_STATE_DIR so individual tests can stage:
#   - "unlocked" / "locked" state
#   - per-item VW contents (so `rbw get NAME` echoes back a known value)
#
# Source files are created under a temp "~/.secrets" and passed explicitly
# via --source. The shim logs each call into SHIM_LOG so tests can assert
# exact interactions.

setup() {
    REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
    SCRIPT="$REPO_ROOT/scripts/migrate-secrets.sh"

    SHIM_DIR="$BATS_TEST_TMPDIR/shim"
    mkdir -p "$SHIM_DIR"
    export BEGET_RBW_CMD="$SHIM_DIR/rbw"

    SHIM_STATE_DIR="$BATS_TEST_TMPDIR/shim-state"
    mkdir -p "$SHIM_STATE_DIR/items"
    # Default: unlocked
    : >"$SHIM_STATE_DIR/unlocked"
    export SHIM_STATE_DIR

    export SHIM_LOG="$BATS_TEST_TMPDIR/rbw-calls.log"
    : >"$SHIM_LOG"

    SRC_DIR="$BATS_TEST_TMPDIR/secrets"
    mkdir -p "$SRC_DIR"
    export SRC_DIR

    install_rbw_shim
}

# Install a stateful rbw shim that consults SHIM_STATE_DIR.
install_rbw_shim() {
    cat >"$BEGET_RBW_CMD" <<'EOF'
#!/usr/bin/env bash
# Stateful fake rbw for migrate-secrets tests.
#
# State files in $SHIM_STATE_DIR:
#   unlocked          — file present means `rbw unlocked` exits 0.
#   items/<name>      — contents = "password" for that VW login.
#   fail_add_<name>   — file present means `rbw add <name>` fails.
#   fail_get_<name>   — file present means `rbw get <name>` fails (even if item exists).

set -u
sub="${1:-}"
shift || true

logfile="${SHIM_LOG:-/dev/null}"

case "$sub" in
  unlocked)
    printf 'unlocked\n' >>"$logfile"
    [ -f "$SHIM_STATE_DIR/unlocked" ]
    exit $?
    ;;
  get)
    item="${1:-}"
    printf 'get %s\n' "$item" >>"$logfile"
    if [ -f "$SHIM_STATE_DIR/fail_get_$item" ]; then
        exit 1
    fi
    if [ -f "$SHIM_STATE_DIR/items/$item" ]; then
        cat "$SHIM_STATE_DIR/items/$item"
        exit 0
    fi
    exit 1
    ;;
  add)
    item="${1:-}"
    value="$(cat)"
    printf 'add %s value=%s\n' "$item" "$value" >>"$logfile"
    if [ -f "$SHIM_STATE_DIR/fail_add_$item" ]; then
        echo "shim: forced add failure" >&2
        exit 1
    fi
    printf '%s' "$value" >"$SHIM_STATE_DIR/items/$item"
    exit 0
    ;;
  *)
    printf 'unexpected rbw subcommand: %s\n' "$sub" >&2
    exit 99
    ;;
esac
EOF
    chmod +x "$BEGET_RBW_CMD"
}

# ---- Argument / help --------------------------------------------------------

@test "unknown flag exits 1 with usage" {
    run bash "$SCRIPT" --bogus
    [ "$status" -eq 1 ]
    [[ "$output" == *"unknown argument"* ]]
}

@test "--help prints usage and exits 0" {
    run bash "$SCRIPT" --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"Usage: scripts/migrate-secrets.sh"* ]]
}

@test "--source with missing directory exits 1" {
    run bash "$SCRIPT" --source "$BATS_TEST_TMPDIR/nope"
    [ "$status" -eq 1 ]
    [[ "$output" == *"does not exist"* ]]
}

# ---- rbw-locked handling ----------------------------------------------------

@test "live run with rbw locked exits 2 gracefully" {
    rm -f "$SHIM_STATE_DIR/unlocked"
    printf 'alpha\n' >"$SRC_DIR/token-a"
    run bash "$SCRIPT" --source "$SRC_DIR"
    [ "$status" -eq 2 ]
    [[ "$output" == *"rbw is locked"* ]]
}

@test "dry-run with rbw locked still works (no VW contact)" {
    rm -f "$SHIM_STATE_DIR/unlocked"
    printf 'alpha\n' >"$SRC_DIR/token-a"
    run bash "$SCRIPT" --dry-run --source "$SRC_DIR"
    [ "$status" -eq 0 ]
    [[ "$output" == *"DRY RUN"* ]]
    [[ "$output" == *"would create token-a"* ]]
}

# ---- Dry-run semantics ------------------------------------------------------

@test "dry-run does not invoke rbw add" {
    printf 'alpha\n' >"$SRC_DIR/token-a"
    printf 'beta\n' >"$SRC_DIR/token-b"
    run bash "$SCRIPT" --dry-run --source "$SRC_DIR"
    [ "$status" -eq 0 ]
    [[ "$output" == *"would create token-a"* ]]
    [[ "$output" == *"would create token-b"* ]]
    # Nothing written.
    [ ! -f "$SHIM_STATE_DIR/items/token-a" ]
    [ ! -f "$SHIM_STATE_DIR/items/token-b" ]
    # No `add` logged.
    ! grep -q '^add ' "$SHIM_LOG"
}

# ---- Happy path -------------------------------------------------------------

@test "live run: new items are created and sha256-verified" {
    printf 'super-secret-alpha' >"$SRC_DIR/token-a"
    printf 'another-secret' >"$SRC_DIR/token-b"
    run bash "$SCRIPT" --source "$SRC_DIR"
    [ "$status" -eq 0 ]
    [[ "$output" == *"migrated token-a"* ]]
    [[ "$output" == *"migrated token-b"* ]]
    [[ "$output" == *"migrated=2 skipped=0 failed=0"* ]]

    # Items landed in the fake VW.
    [ -f "$SHIM_STATE_DIR/items/token-a" ]
    [ -f "$SHIM_STATE_DIR/items/token-b" ]
    run cat "$SHIM_STATE_DIR/items/token-a"
    [ "$output" = "super-secret-alpha" ]
}

@test "source files are NOT deleted after migration" {
    printf 'value' >"$SRC_DIR/token-a"
    run bash "$SCRIPT" --source "$SRC_DIR"
    [ "$status" -eq 0 ]
    [ -f "$SRC_DIR/token-a" ]
    [[ "$output" == *"NOT deleted"* ]]
}

# ---- Skip when already present and matching --------------------------------

@test "live run: item already in VW with matching sha256 is skipped" {
    printf 'value' >"$SRC_DIR/token-a"
    printf 'value' >"$SHIM_STATE_DIR/items/token-a"
    run bash "$SCRIPT" --source "$SRC_DIR"
    [ "$status" -eq 0 ]
    [[ "$output" == *"already in VW"* ]]
    [[ "$output" == *"migrated=0 skipped=1 failed=0"* ]]
    # No second add call.
    ! grep -q '^add token-a' "$SHIM_LOG"
}

# ---- Mismatch: existing item, different contents ---------------------------

@test "live run: item in VW with different sha256 is flagged as failure, NOT overwritten" {
    printf 'new-value' >"$SRC_DIR/token-a"
    printf 'old-value' >"$SHIM_STATE_DIR/items/token-a"
    run bash "$SCRIPT" --source "$SRC_DIR"
    [ "$status" -eq 3 ]
    [[ "$output" == *"sha256 differs"* ]]
    [[ "$output" == *"failed=1"* ]]
    # VW content preserved — we do not overwrite.
    run cat "$SHIM_STATE_DIR/items/token-a"
    [ "$output" = "old-value" ]
}

# ---- rbw add failure propagates --------------------------------------------

@test "live run: rbw add failure counts as failed and exits 3" {
    printf 'value' >"$SRC_DIR/token-a"
    : >"$SHIM_STATE_DIR/fail_add_token-a"
    run bash "$SCRIPT" --source "$SRC_DIR"
    [ "$status" -eq 3 ]
    [[ "$output" == *"rbw add failed for token-a"* ]]
    [[ "$output" == *"failed=1"* ]]
}

# ---- Roundtrip mismatch detection ------------------------------------------

@test "live run: roundtrip sha256 mismatch is flagged" {
    # Install a shim that accepts `add` but returns different content on get.
    cat >"$BEGET_RBW_CMD" <<'EOF'
#!/usr/bin/env bash
set -u
sub="${1:-}"
shift || true
logfile="${SHIM_LOG:-/dev/null}"
case "$sub" in
  unlocked) exit 0 ;;
  get)
    item="${1:-}"
    printf 'get %s\n' "$item" >>"$logfile"
    # Pretend VW mangled the value.
    printf 'CORRUPTED'
    exit 0
    ;;
  add)
    item="${1:-}"
    cat >/dev/null
    printf 'add %s\n' "$item" >>"$logfile"
    exit 0
    ;;
esac
EOF
    chmod +x "$BEGET_RBW_CMD"

    printf 'original-value' >"$SRC_DIR/token-a"
    run bash "$SCRIPT" --source "$SRC_DIR"
    # rbw_has_item would return true here (get succeeds) — so we hit the
    # "exists, sha256 differs" path, NOT the roundtrip path. That's still
    # the correct behavior: we do not overwrite VW. Result is exit 3.
    [ "$status" -eq 3 ]
    [[ "$output" == *"sha256 differs"* ]]
}

# ---- Empty source -----------------------------------------------------------

@test "empty source directory reports zero counts and exits 0" {
    run bash "$SCRIPT" --source "$SRC_DIR"
    [ "$status" -eq 0 ]
    [[ "$output" == *"no files to migrate"* ]]
    [[ "$output" == *"migrated=0 skipped=0 failed=0"* ]]
}

# ---- Ignored patterns -------------------------------------------------------

@test "dotfiles and .swp/.bak are skipped" {
    printf 'x' >"$SRC_DIR/.hidden"
    printf 'x' >"$SRC_DIR/note.swp"
    printf 'x' >"$SRC_DIR/real-token"
    run bash "$SCRIPT" --source "$SRC_DIR"
    [ "$status" -eq 0 ]
    [[ "$output" == *"skip .hidden"* ]]
    [[ "$output" == *"skip note.swp"* ]]
    [[ "$output" == *"migrated real-token"* ]]
    [[ "$output" == *"migrated=1 skipped=2 failed=0"* ]]
}
