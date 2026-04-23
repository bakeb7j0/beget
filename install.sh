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
#   --skip-prereqs   Bypass the preflight scan for distro-managed packages.
#                    Intended for CI/automation environments that have
#                    already run scripts/install-prereqs.sh.
#   --allow-root     Permit running as root (refused by default).
#   --help           Print usage and exit.
#
# This script is PURELY USER-LOCAL — it never calls sudo. Distro-level
# (root-requiring) packages are installed by scripts/install-prereqs.sh.
# If any distro prereq is missing, preflight_root_requirements exits with
# code 3 and a copy-pasteable remediation command.
#
# Environment overrides (test seams):
#   BEGET_RAW_BASE   When set, locate_lib_platform() fetches lib/platform.sh
#                    from "${BEGET_RAW_BASE}/lib/platform.sh" instead of the
#                    default "${BEGET_REPO_URL}/raw/HEAD/lib/platform.sh".
#                    Used by E2E-09 to serve install.sh + lib/ over loopback.
#   BEGET_SKIP_TTY_REPARENT
#                    When set to "1", suppress the /dev/tty stdin reparent.
#                    Used by unit tests exercising the no-TTY code path.
#
# Implements R-01..R-07 and R-43 from docs/beget-devspec.md.

set -euo pipefail

# When piped via `curl ... | bash`, bash's fd 0 is the pipe, so anything the
# script spawns (rbw login) cannot prompt the user. Reparent fd 0 to the
# controlling terminal when one exists. The `|| true` catches the case where
# /dev/tty is present but not openable (no controlling terminal — headless CI,
# some container runtimes, sandboxed subshells). BEGET_SKIP_TTY_REPARENT lets
# tests exercise the downstream no-TTY behavior without spawning a pty.
if [[ "${BEGET_SKIP_TTY_REPARENT:-0}" -ne 1 && ! -t 0 ]]; then
    exec </dev/tty 2>/dev/null || true
fi

# ---- Constants ---------------------------------------------------------------

readonly BEGET_REPO_URL="https://github.com/bakeb7j0/beget"
# BEGET_RAW_BASE: optional override for the raw-fetch base URL. When unset,
# locate_lib_platform() falls back to "${BEGET_REPO_URL}/raw/HEAD". The E2E
# one-liner test (E2E-09) uses this to point at a loopback HTTP server.
readonly BEGET_RAW_BASE="${BEGET_RAW_BASE:-}"
readonly REQUIRED_TOOLS=(curl git bash)

# Exit code emitted by preflight_root_requirements when any distro
# package is missing. Distinct from die()'s generic exit 1 so CI and
# users can distinguish "run install-prereqs.sh first" from real errors.
readonly EXIT_MISSING_PREREQS=3

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
  --skip-prereqs    Bypass preflight scan for distro-managed packages
                    (intended for CI that already ran install-prereqs.sh).
  --skip-apply      Stop after chezmoi init; skip the final 'chezmoi apply'.
                    Useful for staged rollouts and CI bootstrap tests.
  --allow-root      Allow execution as root (refused by default, R-03).
  --help            Show this help and exit.

install.sh is purely user-local: it does not invoke sudo. On fresh
machines, run scripts/install-prereqs.sh as root first to install
distro packages, then run this script as your unprivileged user.

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
    # BEGET_RAW_BASE overrides the default raw base (see script header).
    local tmp raw_base
    if [[ -n "$BEGET_RAW_BASE" ]]; then
        raw_base="$BEGET_RAW_BASE"
    else
        raw_base="${BEGET_REPO_URL}/raw/HEAD"
    fi
    tmp="$(mktemp)"
    if ! curl -fsSL "${raw_base}/lib/platform.sh" -o "$tmp"; then
        rm -f "$tmp"
        die "cannot locate lib/platform.sh (tried $lib_path and ${raw_base}/lib/platform.sh)"
    fi
    printf '%s' "$tmp"
}

# ---- Flag parsing ------------------------------------------------------------

DRY_RUN=0
ROLE="workstation"
SKIP_SECRETS=0
SKIP_APPLY=0
SKIP_PREREQS=0
ALLOW_ROOT=0

parse_flags() {
    local arg
    for arg in "$@"; do
        case "$arg" in
            --dry-run) DRY_RUN=1 ;;
            --role=*) ROLE="${arg#--role=}" ;;
            --skip-secrets) SKIP_SECRETS=1 ;;
            --skip-apply) SKIP_APPLY=1 ;;
            --skip-prereqs) SKIP_PREREQS=1 ;;
            --allow-root) ALLOW_ROOT=1 ;;
            --help | -h)
                usage
                exit 0
                ;;
            *) die "unknown flag: $arg (see --help)" ;;
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

    # Fail fast on the no-TTY-but-secrets-wanted combination. Without this,
    # install would proceed to rbw_prompt_if_needed, which calls `rbw login`,
    # which reads EOF from the pipe and errors with a cryptic message. The
    # stdin reparent at the top of the script already handles the piped-into-
    # terminal case; reaching this check means no /dev/tty was available.
    if [[ "$SKIP_SECRETS" -eq 0 && ! -t 0 ]]; then
        die "no TTY available for interactive rbw login. Either run in an interactive shell, or pass --skip-secrets to bootstrap without secrets (run 'rbw login && chezmoi apply' later to complete)."
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

# ---- Preflight: distro-level prerequisite scan -------------------------------

# Emit the expected distro package list for the detected OS (+ optional
# GNOME desktop pinentry). Called by preflight_root_requirements to
# build the "must be installed" set. OS_ID must already be populated.
expected_distro_pkgs() {
    case "$OS_ID" in
        ubuntu | debian)
            printf '%s\n' \
                pinentry-curses \
                git \
                curl \
                pkg-config \
                libssl-dev \
                build-essential
            ;;
        rocky | rhel | centos | almalinux)
            printf '%s\n' \
                pinentry \
                git \
                curl \
                pkg-config \
                openssl-devel \
                gcc
            ;;
        *)
            die "expected_distro_pkgs: unsupported OS_ID: $OS_ID"
            ;;
    esac
    if is_gnome; then
        printf '%s\n' pinentry-gnome3
    fi
}

# Return 0 if $1 is installed, 1 otherwise. Dispatches per OS_ID.
distro_pkg_installed() {
    local pkg="$1"
    case "$OS_ID" in
        ubuntu | debian)
            dpkg -s "$pkg" >/dev/null 2>&1
            ;;
        rocky | rhel | centos | almalinux)
            rpm -q "$pkg" >/dev/null 2>&1
            ;;
        *)
            die "distro_pkg_installed: unsupported OS_ID: $OS_ID"
            ;;
    esac
}

# Return 0 if the named dnf repo is enabled, 1 otherwise. Rocky/RHEL only.
rocky_repo_enabled() {
    local repo="$1"
    command -v dnf >/dev/null 2>&1 || return 1
    dnf repolist --enabled 2>/dev/null | awk '{print $1}' | grep -Fxq "$repo"
}

# Scan for missing distro packages and exit with EXIT_MISSING_PREREQS if
# any are missing. On success (all present), returns 0 silently.
# Honors --skip-prereqs by returning 0 immediately.
preflight_root_requirements() {
    if [[ "$SKIP_PREREQS" -eq 1 ]]; then
        log "skipping preflight_root_requirements (--skip-prereqs)"
        return 0
    fi

    local expected missing=()
    expected=$(expected_distro_pkgs)

    local pkg
    while IFS= read -r pkg; do
        [[ -n "$pkg" ]] || continue
        if ! distro_pkg_installed "$pkg"; then
            missing+=("$pkg")
        fi
    done <<<"$expected"

    # Rocky-only: EPEL + CRB. Missing either one blocks rbw/direnv builds
    # downstream, so we surface them alongside missing packages.
    local repo_hints=()
    case "$OS_ID" in
        rocky | rhel | centos | almalinux)
            if ! distro_pkg_installed epel-release; then
                missing+=(epel-release)
            fi
            if ! rocky_repo_enabled crb; then
                repo_hints+=("enable CRB repo: dnf config-manager --set-enabled crb")
            fi
            ;;
    esac

    if [[ ${#missing[@]} -eq 0 && ${#repo_hints[@]} -eq 0 ]]; then
        log "distro prereqs OK: $(echo "$expected" | tr '\n' ' ')"
        return 0
    fi

    # Build the copy-pasteable remediation. Prefer the one-step
    # install-prereqs.sh pointer so users don't have to track the
    # full pkg list themselves.
    printf 'ERROR: missing root-installed prerequisites.\n' >&2
    if [[ ${#missing[@]} -gt 0 ]]; then
        printf '  packages: %s\n' "${missing[*]}" >&2
    fi
    if [[ ${#repo_hints[@]} -gt 0 ]]; then
        local hint
        for hint in "${repo_hints[@]}"; do
            printf '  repo: %s\n' "$hint" >&2
        done
    fi
    printf '\n' >&2
    printf 'To remediate, run as root (or via sudo):\n' >&2
    printf '  curl -fsSL %s/raw/HEAD/scripts/install-prereqs.sh | sudo bash\n' "$BEGET_REPO_URL" >&2
    printf '\n' >&2
    printf 'Or install the packages manually with your distro package manager.\n' >&2
    printf 'Then re-run:\n' >&2
    printf '  curl -fsSL %s/raw/HEAD/install.sh | bash\n' "$BEGET_REPO_URL" >&2
    exit "$EXIT_MISSING_PREREQS"
}

# ---- User-local installs (chezmoi, direnv, rbw) ------------------------------

install_user_local() {
    install_chezmoi || die "chezmoi install failed"
    install_direnv || die "direnv install failed"
    install_rbw || die "rbw install failed"
}

# ---- Chezmoi init + apply ----------------------------------------------------

chezmoi_bootstrap() {
    # chezmoi init takes one positional arg (the repo URL). Role is
    # operator-visible in the log only and not plumbed into chezmoi's
    # template engine (separate chore). Secret gating is plumbed via the
    # chezmoi config written by write_chezmoi_config below.
    if [[ "$DRY_RUN" -eq 1 ]]; then
        log "[dry-run] would: chezmoi init ${BEGET_REPO_URL} (role=${ROLE})"
    else
        log "chezmoi init ${BEGET_REPO_URL} (role=${ROLE})"
        chezmoi init "$BEGET_REPO_URL"
    fi
}

# Write a minimal chezmoi config so templates can branch on .skip_secrets.
# Must run BEFORE chezmoi_bootstrap — chezmoi init reads this config when
# evaluating .chezmoiignore.tmpl and any other templates invoked during init.
# Honors DRY_RUN by logging instead of writing.
write_chezmoi_config() {
    local config_dir="${HOME}/.config/chezmoi"
    local config_path="${config_dir}/chezmoi.toml"
    local skip_secrets_bool
    if [[ "$SKIP_SECRETS" -eq 1 ]]; then
        skip_secrets_bool="true"
    else
        skip_secrets_bool="false"
    fi

    if [[ "$DRY_RUN" -eq 1 ]]; then
        log "[dry-run] would write ${config_path} with skip_secrets=${skip_secrets_bool}"
        return 0
    fi

    mkdir -p "$config_dir"
    cat >"$config_path" <<TOML
# Auto-generated by install.sh. Set via --skip-secrets flag.
# Regenerated on every install.sh run.
[data]
    skip_secrets = ${skip_secrets_bool}
TOML
    log "wrote ${config_path} (skip_secrets=${skip_secrets_bool})"
}

rbw_prompt_if_needed() {
    if [[ "$SKIP_SECRETS" -eq 1 ]]; then
        log "skipping rbw (--skip-secrets)"
        return 0
    fi

    if ! command -v rbw >/dev/null 2>&1; then
        die "rbw not found after prereq install"
    fi

    # rbw 1.15.0 has no `status` subcommand — valid subcommands at the time
    # of writing are `unlocked`, `unlock`, `login`, `get`, `config`. Probing
    # via a subcommand name couples install.sh to a specific rbw release;
    # check for the config file instead, which is the canonical artifact
    # `rbw login` produces on first success.
    local rbw_config="${HOME}/.config/rbw/config.json"
    if [[ -f "$rbw_config" ]]; then
        log "rbw already configured ($rbw_config)"
        return 0
    fi

    if [[ "$DRY_RUN" -eq 1 ]]; then
        log "[dry-run] would prompt: rbw login"
        return 0
    fi

    log "rbw not configured — running: rbw login"
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
    preflight_root_requirements
    install_user_local
    write_chezmoi_config
    chezmoi_bootstrap
    rbw_prompt_if_needed
    if [[ "$SKIP_APPLY" -eq 1 ]]; then
        log "--skip-apply set; chezmoi apply skipped (run 'chezmoi apply' manually when ready)"
    else
        chezmoi_apply
    fi

    log "bootstrap complete — role=${ROLE}"
    log "next: open a fresh shell and run 'chezmoi apply' again to pick up any follow-on changes."
}

# Only run main when executed directly — sourcing for tests is supported via
# BEGET_INSTALL_SOURCED=1.
if [[ "${BEGET_INSTALL_SOURCED:-0}" -ne 1 ]]; then
    main "$@"
fi
