#!/usr/bin/env bash
# lib/platform.sh — OS detection and user-local installers.
#
# Sourced library. Do NOT set -euo pipefail globally here — a library must
# not alter the caller's shell options. Individual functions use `local`
# variables and explicit return codes.
#
# This library intentionally contains ZERO sudo calls. Distro-level
# (root-requiring) packages are installed by scripts/install-prereqs.sh
# in a separate, explicit step; install.sh scans for them in preflight
# and exits with actionable guidance if anything is missing. See #100.
#
# Public functions:
#   source_os_release          — populate OS_ID and OS_MAJOR_VERSION
#   pkg_name_pinentry_tty      — print distro-appropriate curses pinentry pkg name
#   is_gnome                   — return 0 if running under GNOME
#   die_if_unsupported_os      — abort if OS is not Ubuntu 24.04 or Rocky 9
#   install_chezmoi            — install chezmoi via upstream get.chezmoi.io
#   install_direnv             — install direnv via upstream direnv.net
#   ensure_rust_toolchain      — install rustup + stable toolchain (user-local)
#   install_rbw                — install rbw via cargo (builds toolchain if needed)
#
# Test seams (env-var overrides, default shown):
#   OS_RELEASE_FILE        — /etc/os-release
#   BEGET_CHEZMOI_INSTALLER — https://get.chezmoi.io
#   BEGET_DIRENV_INSTALLER  — https://direnv.net/install.sh
#   BEGET_RUSTUP_INSTALLER  — https://sh.rustup.rs
#   DRY_RUN                — when 1, install_chezmoi/install_direnv/install_rbw log intent only

# Emit an error and exit non-zero. Used for clean aborts.
die() {
    printf 'ERROR: %s\n' "$*" >&2
    exit 1
}

# Read /etc/os-release (or OS_RELEASE_FILE override) and export OS_ID +
# OS_MAJOR_VERSION. Uses a subshell to avoid leaking other variables the
# file may define.
source_os_release() {
    local os_release_file="${OS_RELEASE_FILE:-/etc/os-release}"
    if [[ ! -r "$os_release_file" ]]; then
        die "cannot read os-release file: $os_release_file"
    fi

    local id version_id major
    # shellcheck disable=SC1090
    id=$(. "$os_release_file" && printf '%s' "${ID:-}")
    # shellcheck disable=SC1090
    version_id=$(. "$os_release_file" && printf '%s' "${VERSION_ID:-}")

    if [[ -z "$id" ]]; then
        die "os-release missing ID field"
    fi

    # Extract leading numeric component of VERSION_ID (e.g. "24.04" -> "24",
    # "9" -> "9", "9.3" -> "9"). If empty, leave OS_MAJOR_VERSION empty.
    major="${version_id%%.*}"

    export OS_ID="$id"
    export OS_MAJOR_VERSION="$major"
}

# Resolve the distro-appropriate package name for the curses/TTY
# pinentry. Debian/Ubuntu ship it as `pinentry-curses`; RHEL-family
# dnf repos ship it as plain `pinentry` (no `-curses` suffix because
# that's the only pinentry variant in the base repos). Consumed by
# callers building distro-package lists for preflight scans.
pkg_name_pinentry_tty() {
    if [[ -z "${OS_ID:-}" ]]; then
        source_os_release
    fi
    case "$OS_ID" in
        ubuntu | debian) printf 'pinentry-curses' ;;
        rocky | rhel | centos | almalinux | fedora) printf 'pinentry' ;;
        *) die "pkg_name_pinentry_tty: unsupported OS_ID: $OS_ID" ;;
    esac
}

# Return 0 if running under a GNOME desktop session, 1 otherwise.
# Heuristic: the string "GNOME" appears (case-insensitive) in
# XDG_CURRENT_DESKTOP.
is_gnome() {
    local desktop="${XDG_CURRENT_DESKTOP:-}"
    if [[ "${desktop,,}" == *gnome* ]]; then
        return 0
    fi
    return 1
}

log_platform() {
    printf '[platform] %s\n' "$*"
}

# Prepend a directory to PATH if it's not already present. Idempotent.
_prepend_path() {
    local dir="$1"
    case ":${PATH}:" in
        *":${dir}:"*) return 0 ;;
    esac
    export PATH="${dir}:${PATH}"
}

# Install chezmoi via the upstream installer (user-local, no sudo).
# Noop when chezmoi is already on PATH. Honors DRY_RUN.
install_chezmoi() {
    local bindir="${HOME}/.local/bin"

    if command -v chezmoi >/dev/null 2>&1; then
        log_platform "chezmoi already installed at $(command -v chezmoi)"
        return 0
    fi

    if [[ "${DRY_RUN:-0}" -eq 1 ]]; then
        log_platform "[dry-run] would install chezmoi via get.chezmoi.io into ${bindir}"
        return 0
    fi

    mkdir -p "$bindir"
    local installer="${BEGET_CHEZMOI_INSTALLER:-https://get.chezmoi.io}"
    log_platform "installing chezmoi from ${installer} into ${bindir}"
    # Capture the installer script separately: a sourced library can't set
    # -o pipefail, so curl|sh would silently swallow a curl failure.
    local script
    script=$(curl -fsSL "$installer") ||
        die "install_chezmoi: failed to fetch installer: $installer"
    printf '%s\n' "$script" | sh -s -- -b "$bindir"
    _prepend_path "$bindir"
}

# Install direnv via the upstream direnv.net installer (user-local,
# no sudo). direnv is in Debian/Ubuntu apt but NOT in Rocky/RHEL 9 repos
# (neither base nor EPEL ship it), so the upstream binary is the only
# uniform install path. Noop when direnv is already on PATH.
install_direnv() {
    local bindir="${HOME}/.local/bin"

    if command -v direnv >/dev/null 2>&1; then
        log_platform "direnv already installed at $(command -v direnv)"
        return 0
    fi

    if [[ "${DRY_RUN:-0}" -eq 1 ]]; then
        log_platform "[dry-run] would install direnv via direnv.net into ${bindir}"
        return 0
    fi

    mkdir -p "$bindir"
    local installer="${BEGET_DIRENV_INSTALLER:-https://direnv.net/install.sh}"
    log_platform "installing direnv from ${installer} into ${bindir}"
    # Capture the installer script separately to surface curl failures
    # (sourced libraries can't set -o pipefail).
    local script
    script=$(curl -fsSL "$installer") ||
        die "install_direnv: failed to fetch installer: $installer"
    # direnv's installer honors bin_path for relocation.
    printf '%s\n' "$script" | bin_path="$bindir" bash
    _prepend_path "$bindir"
}

# Ensure a Rust toolchain meeting rbw's MSRV is available via rustup.
# rbw 1.15 requires rustc 1.82+, which exceeds both Ubuntu 24.04 (1.75)
# and Rocky 9's distro cargo, so we bootstrap rustup to ~/.cargo/bin
# when the existing cargo is missing or too old. rustup is the Rust
# community's canonical installer and keeps the toolchain user-local
# (no sudo required).
ensure_rust_toolchain() {
    local cargo_bindir="${HOME}/.cargo/bin"
    _prepend_path "$cargo_bindir"

    if command -v cargo >/dev/null 2>&1 && command -v rustc >/dev/null 2>&1; then
        # Check rustc is at least 1.82. `rustc --version` → "rustc X.Y.Z (...)"
        local rustc_ver
        rustc_ver=$(rustc --version | awk '{print $2}')
        local major minor
        major="${rustc_ver%%.*}"
        minor="${rustc_ver#*.}"
        minor="${minor%%.*}"
        if [[ "$major" -gt 1 || ("$major" -eq 1 && "$minor" -ge 82) ]]; then
            log_platform "rust toolchain ${rustc_ver} meets rbw MSRV (1.82)"
            return 0
        fi
        log_platform "rust toolchain ${rustc_ver} below rbw MSRV (1.82) — bootstrapping via rustup"
    else
        log_platform "no cargo on PATH — bootstrapping rust via rustup"
    fi

    local installer="${BEGET_RUSTUP_INSTALLER:-https://sh.rustup.rs}"
    # Capture the installer script separately to surface curl failures
    # (sourced libraries can't set -o pipefail).
    local script
    script=$(curl --proto '=https' --tlsv1.2 -fsSL "$installer") ||
        die "ensure_rust_toolchain: failed to fetch rustup installer: $installer"
    printf '%s\n' "$script" | sh -s -- -y --default-toolchain stable --profile minimal
    _prepend_path "$cargo_bindir"
}

# Install rbw via cargo. Noop when rbw is already on PATH. Honors DRY_RUN.
# The native build deps (pkg-config, openssl dev headers, C compiler) are
# expected to be pre-installed by scripts/install-prereqs.sh and verified
# by install.sh's preflight_root_requirements scan. A modern Rust toolchain
# is ensured through rustup (distro cargo on Ubuntu 24.04 / Rocky 9 is too
# old — see ensure_rust_toolchain), then we invoke `cargo install rbw --locked`.
install_rbw() {
    local cargo_bindir="${HOME}/.cargo/bin"

    if command -v rbw >/dev/null 2>&1; then
        log_platform "rbw already installed at $(command -v rbw)"
        return 0
    fi

    if [[ "${DRY_RUN:-0}" -eq 1 ]]; then
        log_platform "[dry-run] would ensure rust toolchain via rustup"
        log_platform "[dry-run] would cargo install rbw --locked into ${cargo_bindir}"
        return 0
    fi

    ensure_rust_toolchain

    log_platform "cargo install rbw --locked (this can take 5-10 minutes)"
    cargo install rbw --locked
    _prepend_path "$cargo_bindir"
}

# Abort with a clear message unless the detected OS is in the supported set.
# Supported: Ubuntu 24.04, Rocky 9.
die_if_unsupported_os() {
    if [[ -z "${OS_ID:-}" || -z "${OS_MAJOR_VERSION:-}" ]]; then
        source_os_release
    fi

    case "${OS_ID}:${OS_MAJOR_VERSION}" in
        ubuntu:24)
            return 0
            ;;
        rocky:9)
            return 0
            ;;
        *)
            die "unsupported OS: ${OS_ID} ${OS_MAJOR_VERSION} (supported: Ubuntu 24.04, Rocky 9)"
            ;;
    esac
}
