#!/usr/bin/env bash
# install.sh — beget bootstrap entry point
#
# One-liner invocation:
#   curl -fsSL https://github.com/bakeb7j0/beget/raw/HEAD/install.sh | bash
#
# Flags:
#   --dry-run        Show what would happen without mutating the system.
#   --role=<X>       Pass a role tag (workstation|server|minimal) to chezmoi.
#   --skip-secrets   Bootstrap without rbw login or secret materialization.
#   --allow-root     Permit running as root (refused by default).
#   --help           Print usage and exit.
#
# Implements R-01..R-07 and R-43 from docs/beget-devspec.md.

set -euo pipefail

# ---- Constants ---------------------------------------------------------------

readonly BEGET_REPO_URL="https://github.com/bakeb7j0/beget"
readonly REQUIRED_TOOLS=(curl git bash)
# Always-install prereqs. pinentry-gnome3 added conditionally below.
readonly BASE_PREREQS=(chezmoi rbw direnv pinentry-curses git curl)

# ---- Helpers -----------------------------------------------------------------

log() {
    printf '[install] %s\n' "$*"
}

die() {
    printf 'ERROR: %s\n' "$*" >&2
    exit 1
}

usage() {
    cat <<'USAGE'
Usage: install.sh [options]

Bootstrap a beget-managed environment via chezmoi.

Options:
  --dry-run         Print actions without executing them.
  --role=<X>        Role tag to pass to chezmoi (workstation|server|minimal).
                    Defaults to "workstation".
  --skip-secrets    Skip rbw login and secret materialization.
  --allow-root      Allow execution as root (refused by default, R-03).
  --help            Show this help and exit.

Example:
  curl -fsSL https://github.com/bakeb7j0/beget/raw/HEAD/install.sh \
    | bash -s -- --role=workstation --skip-secrets
USAGE
}

# Locate the repo root containing lib/platform.sh. When running from a clone
# we can compute it from the script path; when piped via curl we fall back to
# fetching the library from the remote raw URL.
locate_lib_platform() {
    local script_dir lib_path raw_dir
    raw_dir="$(dirname "${BASH_SOURCE[0]:-$0}")"
    if script_dir="$(cd "$raw_dir" 2>/dev/null && pwd)"; then
        lib_path="${script_dir}/lib/platform.sh"
        if [[ -r "$lib_path" ]]; then
            printf '%s' "$lib_path"
            return 0
        fi
    fi

    # Fallback: curl-piped path. Download lib/platform.sh to a temp file.
    local tmp
    tmp="$(mktemp)"
    if ! curl -fsSL "${BEGET_REPO_URL}/raw/HEAD/lib/platform.sh" -o "$tmp"; then
        rm -f "$tmp"
        die "cannot locate lib/platform.sh (tried $lib_path and remote fetch)"
    fi
    printf '%s' "$tmp"
}

# ---- Flag parsing ------------------------------------------------------------

DRY_RUN=0
ROLE="workstation"
SKIP_SECRETS=0
ALLOW_ROOT=0

parse_flags() {
    local arg
    for arg in "$@"; do
        case "$arg" in
            --dry-run)       DRY_RUN=1 ;;
            --role=*)        ROLE="${arg#--role=}" ;;
            --skip-secrets)  SKIP_SECRETS=1 ;;
            --allow-root)    ALLOW_ROOT=1 ;;
            --help|-h)       usage; exit 0 ;;
            *)               die "unknown flag: $arg (see --help)" ;;
        esac
    done

    if [[ -z "$ROLE" ]]; then
        die "--role requires a value (e.g. --role=workstation)"
    fi
}

# ---- Pre-flight --------------------------------------------------------------

# Current effective UID. Factored out so tests can override by redefining
# this function — EUID is readonly in bash and cannot be changed directly.
current_euid() {
    id -u
}

preflight() {
    # R-03: reject root unless --allow-root.
    if [[ "$(current_euid)" -eq 0 && "$ALLOW_ROOT" -ne 1 ]]; then
        die "refusing to run as root; pass --allow-root to override (R-03)"
    fi

    # Required tools present?
    local tool
    for tool in "${REQUIRED_TOOLS[@]}"; do
        if ! command -v "$tool" >/dev/null 2>&1; then
            die "missing required tool: $tool (install it first)"
        fi
    done

    # Network reachable?
    if ! curl -fsS --max-time 10 -o /dev/null "https://github.com"; then
        die "cannot reach https://github.com — check network connectivity"
    fi

    # OS detection and support check (R-02).
    source_os_release
    die_if_unsupported_os

    log "pre-flight OK: role=${ROLE} os=${OS_ID}:${OS_MAJOR_VERSION} dry_run=${DRY_RUN} skip_secrets=${SKIP_SECRETS}"
}

# ---- Prereq install ----------------------------------------------------------

install_prereqs() {
    local pkgs=("${BASE_PREREQS[@]}")

    # pinentry-gnome3 is only meaningful on GNOME desktops.
    if is_gnome; then
        pkgs+=(pinentry-gnome3)
    fi

    if [[ "$DRY_RUN" -eq 1 ]]; then
        log "[dry-run] would pkg_install: ${pkgs[*]}"
        return 0
    fi

    log "installing prereqs: ${pkgs[*]}"
    pkg_install "${pkgs[@]}"
}

# ---- Chezmoi init + apply ----------------------------------------------------

chezmoi_bootstrap() {
    if [[ "$DRY_RUN" -eq 1 ]]; then
        log "[dry-run] would: chezmoi init ${BEGET_REPO_URL} --data role=${ROLE}"
    else
        log "chezmoi init ${BEGET_REPO_URL} --data role=${ROLE}"
        chezmoi init "$BEGET_REPO_URL" --data "role=${ROLE}"
    fi
}

rbw_prompt_if_needed() {
    if [[ "$SKIP_SECRETS" -eq 1 ]]; then
        log "skipping rbw (--skip-secrets)"
        return 0
    fi

    if ! command -v rbw >/dev/null 2>&1; then
        die "rbw not found after prereq install"
    fi

    if rbw status >/dev/null 2>&1; then
        log "rbw already logged in"
        return 0
    fi

    if [[ "$DRY_RUN" -eq 1 ]]; then
        log "[dry-run] would prompt: rbw login"
        return 0
    fi

    log "rbw not logged in — running: rbw login"
    rbw login
}

chezmoi_apply() {
    local apply_args=(--verbose)
    if [[ "$DRY_RUN" -eq 1 ]]; then
        apply_args+=(--dry-run)
    fi

    log "chezmoi apply ${apply_args[*]}"
    chezmoi apply "${apply_args[@]}"
}

# ---- Main --------------------------------------------------------------------

main() {
    parse_flags "$@"

    local lib_path
    lib_path="$(locate_lib_platform)"
    # shellcheck source=/dev/null
    source "$lib_path"

    preflight
    install_prereqs
    chezmoi_bootstrap
    rbw_prompt_if_needed
    chezmoi_apply

    log "bootstrap complete — role=${ROLE}"
    log "next: open a fresh shell and run 'chezmoi apply' again to pick up any follow-on changes."
}

# Only run main when executed directly — sourcing for tests is supported via
# BEGET_INSTALL_SOURCED=1.
if [[ "${BEGET_INSTALL_SOURCED:-0}" -ne 1 ]]; then
    main "$@"
fi
