#!/usr/bin/env bash
# scripts/migrate-secrets.sh — one-shot migration of ~/.secrets/ into Vaultwarden.
#
# Walks every regular file under the source directory (default ~/.secrets,
# falling back to ~/secrets), creates a Login item in Vaultwarden per file
# with the file's contents as the password, and verifies the sha256 of the
# stored value matches the source. Existing items are left alone unless
# their sha256 already matches (treated as a skip).
#
# DOES NOT delete source files. That is a manual step for BJ after visual
# confirmation.
#
# Usage:
#   scripts/migrate-secrets.sh                Migrate everything (live run).
#   scripts/migrate-secrets.sh --dry-run      Report what would happen; no VW writes.
#   scripts/migrate-secrets.sh --source DIR   Migrate from DIR (explicit).
#   scripts/migrate-secrets.sh --help         Print usage.
#
# Exit codes:
#   0  success (no failures)
#   1  usage / precondition error
#   2  rbw locked / unreachable
#   3  one or more files failed to migrate
#
# Test seams (env-var overrides):
#   BEGET_RBW_CMD         name of the rbw binary (default: rbw).
#   BEGET_SHA256_CMD      name of the sha256 binary (default: sha256sum).
#
# References: S2.5 (bakeb7j0/beget#14), DM-15 in docs/beget-devspec.md.

set -euo pipefail

# ---- Defaults ---------------------------------------------------------------

BEGET_RBW_CMD="${BEGET_RBW_CMD:-rbw}"
BEGET_SHA256_CMD="${BEGET_SHA256_CMD:-sha256sum}"

DRY_RUN=0
SOURCE_DIR=""

# Counters for the summary block.
count_migrated=0
count_skipped=0
count_failed=0

# Collected failure details (for the summary).
failed_names=()

# ---- Helpers ----------------------------------------------------------------

usage() {
    cat <<'USAGE'
Usage: scripts/migrate-secrets.sh [options]

Migrate files from ~/.secrets/ (or ~/secrets/) into Vaultwarden. Each file
becomes a Login item whose password equals the file contents. The source
files are NEVER deleted by this tool.

Options:
  --dry-run         Report what would happen without writing to Vaultwarden.
  --source DIR      Explicit source directory (default: ~/.secrets, then ~/secrets).
  --help            Show this help and exit.

Exit codes:
  0  success
  1  usage / precondition error
  2  rbw locked / unreachable
  3  one or more files failed to migrate
USAGE
}

log() {
    printf '[migrate] %s\n' "$*"
}

warn() {
    printf 'WARN: %s\n' "$*" >&2
}

die() {
    printf 'ERROR: %s\n' "$*" >&2
    exit 1
}

# Compute sha256 of stdin. Accepts `sha256sum` (Linux) or `shasum -a 256`
# style output by taking the first whitespace-separated field.
sha256_of() {
    local cmd="$BEGET_SHA256_CMD"
    # shellcheck disable=SC2016
    "$cmd" | awk '{print $1; exit}'
}

# Check whether rbw is unlocked. Returns 0 if ready, non-zero otherwise.
rbw_ready() {
    "$BEGET_RBW_CMD" unlocked >/dev/null 2>&1
}

# Return 0 if a VW item with NAME exists. Non-zero otherwise.
rbw_has_item() {
    local name="$1"
    "$BEGET_RBW_CMD" get "$name" >/dev/null 2>&1
}

# Print the password of item NAME to stdout. Caller discards on failure.
rbw_read_item() {
    local name="$1"
    "$BEGET_RBW_CMD" get "$name"
}

# Create a VW Login item NAME with password taken from stdin.
rbw_create_item() {
    local name="$1"
    "$BEGET_RBW_CMD" add "$name"
}

# ---- Argument parsing -------------------------------------------------------

while [[ $# -gt 0 ]]; do
    case "$1" in
        --dry-run)
            DRY_RUN=1
            shift
            ;;
        --source)
            [[ $# -ge 2 ]] || die "--source requires a directory argument"
            SOURCE_DIR="$2"
            shift 2
            ;;
        --source=*)
            SOURCE_DIR="${1#--source=}"
            shift
            ;;
        --help|-h)
            usage
            exit 0
            ;;
        *)
            usage >&2
            die "unknown argument: $1"
            ;;
    esac
done

# ---- Source resolution ------------------------------------------------------

if [[ -z "$SOURCE_DIR" ]]; then
    if [[ -d "$HOME/.secrets" ]]; then
        SOURCE_DIR="$HOME/.secrets"
    elif [[ -d "$HOME/secrets" ]]; then
        SOURCE_DIR="$HOME/secrets"
    else
        die "no source directory found (tried ~/.secrets and ~/secrets). Use --source DIR."
    fi
fi

[[ -d "$SOURCE_DIR" ]] || die "source directory does not exist: $SOURCE_DIR"

# ---- Precondition: rbw reachable -------------------------------------------

if [[ "$DRY_RUN" -eq 0 ]]; then
    if ! rbw_ready; then
        warn "rbw is locked or Vaultwarden is unreachable."
        warn "Run 'rbw unlock' (and 'rbw sync' if needed) and try again."
        exit 2
    fi
fi

# ---- Walk + migrate ---------------------------------------------------------

log "source: $SOURCE_DIR"
if [[ "$DRY_RUN" -eq 1 ]]; then
    log "mode: DRY RUN (no Vaultwarden writes)"
else
    log "mode: LIVE"
fi

# Collect candidate files. Only regular files (ignore symlinks, sockets, etc.)
# Sort for deterministic output.
mapfile -t files < <(find "$SOURCE_DIR" -maxdepth 1 -type f -print | LC_ALL=C sort)

if [[ "${#files[@]}" -eq 0 ]]; then
    log "no files to migrate."
    echo
    log "Summary: migrated=0 skipped=0 failed=0"
    exit 0
fi

for file in "${files[@]}"; do
    name="$(basename "$file")"
    # Skip hidden dotfiles and any obvious non-secret detritus.
    case "$name" in
        .*|*.swp|*.bak)
            log "skip $name (ignored pattern)"
            count_skipped=$((count_skipped + 1))
            continue
            ;;
    esac

    # Compute source hash.
    if ! src_hash="$(sha256_of <"$file")" || [[ -z "$src_hash" ]]; then
        warn "failed to hash $name"
        count_failed=$((count_failed + 1))
        failed_names+=("$name (hash error)")
        continue
    fi

    if [[ "$DRY_RUN" -eq 1 ]]; then
        if rbw_has_item "$name" 2>/dev/null; then
            log "would check $name (exists in VW — compare sha256)"
        else
            log "would create $name (sha256=$src_hash)"
        fi
        count_migrated=$((count_migrated + 1))
        continue
    fi

    # Live path: does VW already have this item?
    if rbw_has_item "$name"; then
        if existing="$(rbw_read_item "$name")"; then
            existing_hash="$(printf '%s' "$existing" | sha256_of)"
            if [[ "$existing_hash" == "$src_hash" ]]; then
                log "skip $name (already in VW; sha256 matches)"
                count_skipped=$((count_skipped + 1))
                continue
            fi
            warn "$name exists in VW but sha256 differs (src=$src_hash vw=$existing_hash)"
            warn "  leaving VW item untouched. Resolve manually."
            count_failed=$((count_failed + 1))
            failed_names+=("$name (sha256 mismatch)")
            continue
        fi
        warn "$name exists in VW but could not be read"
        count_failed=$((count_failed + 1))
        failed_names+=("$name (read error)")
        continue
    fi

    # Create it. Pipe the file in so rbw reads it as the item password.
    if ! rbw_create_item "$name" <"$file"; then
        warn "rbw add failed for $name"
        count_failed=$((count_failed + 1))
        failed_names+=("$name (rbw add failed)")
        continue
    fi

    # Roundtrip verify.
    if ! roundtrip="$(rbw_read_item "$name")"; then
        warn "$name created but read-back failed"
        count_failed=$((count_failed + 1))
        failed_names+=("$name (roundtrip read failed)")
        continue
    fi

    roundtrip_hash="$(printf '%s' "$roundtrip" | sha256_of)"
    if [[ "$roundtrip_hash" != "$src_hash" ]]; then
        warn "$name created but sha256 roundtrip MISMATCH (src=$src_hash vw=$roundtrip_hash)"
        count_failed=$((count_failed + 1))
        failed_names+=("$name (roundtrip mismatch)")
        continue
    fi

    log "migrated $name (sha256 verified)"
    count_migrated=$((count_migrated + 1))
done

# ---- Summary ----------------------------------------------------------------

echo
log "Summary: migrated=$count_migrated skipped=$count_skipped failed=$count_failed"
if [[ "${#failed_names[@]}" -gt 0 ]]; then
    log "Failures:"
    for n in "${failed_names[@]}"; do
        log "  - $n"
    done
fi

# Remind the operator source files are untouched.
if [[ "$DRY_RUN" -eq 0 && "$count_migrated" -gt 0 ]]; then
    log "source files were NOT deleted. Review and remove manually when satisfied."
fi

if [[ "$count_failed" -gt 0 ]]; then
    exit 3
fi
exit 0
