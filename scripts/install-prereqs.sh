#!/usr/bin/env bash
# scripts/install-prereqs.sh — install the distro-level (root-requiring)
# prerequisites that install.sh needs. Must be run as root (or via sudo).
#
# install.sh is purely user-local and no longer invokes sudo itself. On
# fresh machines, run this script once (it's the only root-requiring step
# in the whole bootstrap), then run install.sh as the unprivileged user.
#
# Usage:
#     sudo bash scripts/install-prereqs.sh [--dry-run]
#   or one-liner:
#     curl -fsSL https://raw.githubusercontent.com/bakeb7j0/beget/main/scripts/install-prereqs.sh | sudo bash
#
# Flags:
#   --dry-run   Print the commands that would be run, without executing them.
#   --help      Show this help and exit.
#
# Packages installed (matches what install.sh + chezmoi templates need):
#   Ubuntu 24.04: pinentry-curses git curl pkg-config libssl-dev
#                 build-essential  (+ pinentry-gnome3 under GNOME)
#   Rocky 9:      pinentry git curl pkg-config openssl-devel gcc
#                 (+ pinentry-gnome3 under GNOME), plus epel-release and
#                 the CRB repo enabled (EPEL userspace depends on CRB).
#
# Exit codes:
#   0 — success
#   1 — generic failure (package manager error, unsupported OS, etc.)
#   2 — invoked as non-root while --dry-run was not set
#
# Test seams (env overrides):
#   OS_RELEASE_FILE   — path to os-release file (default /etc/os-release)
#   BEGET_PREREQS_PKG_CMD — override package-manager command for tests
#
# This script is intentionally self-contained: it does not source
# lib/platform.sh, so users can `curl | sudo bash` it without having the
# repo checked out first.

set -euo pipefail

DRY_RUN=0
USAGE=$(
    cat <<'EOF'
Usage: install-prereqs.sh [--dry-run] [--help]

Installs the distro-level prerequisites that install.sh needs. Must be
run as root (or via sudo); see `--dry-run` for a preview without root.
EOF
)

die() {
    printf 'ERROR: %s\n' "$*" >&2
    exit 1
}

log() {
    printf '[install-prereqs] %s\n' "$*"
}

parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --dry-run) DRY_RUN=1 ;;
            --help | -h)
                printf '%s\n' "$USAGE"
                exit 0
                ;;
            *) die "unknown argument: $1 (try --help)" ;;
        esac
        shift
    done
}

require_root() {
    if [[ "${DRY_RUN}" -eq 1 ]]; then
        return 0
    fi
    if [[ "${EUID:-$(id -u)}" -ne 0 ]]; then
        printf 'ERROR: this script must be run as root (or via sudo).\n' >&2
        printf 'Try: sudo bash %s\n' "$0" >&2
        exit 2
    fi
}

detect_os() {
    local os_release_file="${OS_RELEASE_FILE:-/etc/os-release}"
    if [[ ! -r "$os_release_file" ]]; then
        die "cannot read os-release file: $os_release_file"
    fi

    local version_id
    # shellcheck disable=SC1090
    OS_ID=$(. "$os_release_file" && printf '%s' "${ID:-}")
    # shellcheck disable=SC1090
    version_id=$(. "$os_release_file" && printf '%s' "${VERSION_ID:-}")

    [[ -n "${OS_ID}" ]] || die "os-release missing ID field"
    OS_MAJOR_VERSION="${version_id%%.*}"
}

is_gnome() {
    local desktop="${XDG_CURRENT_DESKTOP:-}"
    [[ "${desktop,,}" == *gnome* ]]
}

run_cmd() {
    if [[ "${DRY_RUN}" -eq 1 ]]; then
        log "[dry-run] $*"
        return 0
    fi
    log "+ $*"
    "$@"
}

install_ubuntu() {
    local pkgs=(pinentry-curses git curl pkg-config libssl-dev build-essential)
    if is_gnome; then
        pkgs+=(pinentry-gnome3)
    fi

    run_cmd apt-get update -qq
    run_cmd apt-get install -y "${pkgs[@]}"
}

install_rocky() {
    local pkgs=(pinentry git curl pkg-config openssl-devel gcc)
    if is_gnome; then
        pkgs+=(pinentry-gnome3)
    fi

    # EPEL first, then CRB. Several chezmoi-layer tools (direnv most
    # notably) live in EPEL, which itself depends on CRB being enabled.
    if [[ "${DRY_RUN}" -eq 1 ]] || ! rpm -q epel-release >/dev/null 2>&1; then
        run_cmd dnf install -y epel-release
    else
        log "epel-release already installed"
    fi
    run_cmd dnf config-manager --set-enabled crb

    run_cmd dnf makecache -q
    run_cmd dnf install -y "${pkgs[@]}"
}

main() {
    parse_args "$@"
    require_root
    detect_os

    log "detected OS: ${OS_ID} ${OS_MAJOR_VERSION}"

    case "${OS_ID}" in
        ubuntu | debian)
            install_ubuntu
            ;;
        rocky | rhel | centos | almalinux)
            install_rocky
            ;;
        *)
            die "unsupported OS: ${OS_ID} (expected ubuntu or rocky/rhel)"
            ;;
    esac

    log "prereqs installed. Now run install.sh as your unprivileged user:"
    log "    curl -fsSL https://raw.githubusercontent.com/bakeb7j0/beget/main/install.sh | bash"
}

main "$@"
