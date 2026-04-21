#!/usr/bin/env bash
# lib/platform.sh — OS detection and package manager abstraction
#
# Sourced library. Do NOT set -euo pipefail globally here — a library must
# not alter the caller's shell options. Individual functions use `local`
# variables and explicit return codes.
#
# Public functions:
#   source_os_release          — populate OS_ID and OS_MAJOR_VERSION
#   pkg_install <pkg>...       — install packages via apt-get or dnf
#   pkg_repo_add <url> <keyring_url> <name>
#                              — register an apt or yum repo
#   is_gnome                   — return 0 if running under GNOME
#   die_if_unsupported_os      — abort if OS is not Ubuntu 24.04 or Rocky 9
#   install_chezmoi            — install chezmoi via upstream get.chezmoi.io
#   install_direnv             — install direnv via upstream direnv.net
#   install_rbw                — install rbw via cargo (builds toolchain if needed)
#
# Test seams (env-var overrides, default shown):
#   OS_RELEASE_FILE        — /etc/os-release
#   APT_SOURCES_DIR        — /etc/apt/sources.list.d
#   YUM_REPOS_DIR          — /etc/yum.repos.d
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

# Refresh the package manager's metadata cache. Cheap on an up-to-date
# system and essential on one with stale / empty lists (e.g. a minimal
# container with /var/lib/apt/lists/ pruned, or a long-idle VM). Called
# automatically by pkg_install on first invocation per process.
_pkg_cache_refreshed=0
pkg_cache_refresh() {
    if [[ "$_pkg_cache_refreshed" -eq 1 ]]; then
        return 0
    fi

    if [[ -z "${OS_ID:-}" ]]; then
        source_os_release
    fi

    case "$OS_ID" in
        ubuntu | debian)
            sudo apt-get update -qq
            ;;
        rocky | rhel | centos | almalinux | fedora)
            # dnf makecache is a noop when metadata is fresh; honor its
            # own age heuristics rather than forcing a full refresh.
            sudo dnf makecache -q
            ;;
        *)
            die "pkg_cache_refresh: unsupported OS_ID: $OS_ID"
            ;;
    esac

    _pkg_cache_refreshed=1
}

# Install one or more packages using the native package manager.
# Dispatches based on OS_ID (populated by source_os_release).
pkg_install() {
    if [[ $# -eq 0 ]]; then
        die "pkg_install: no packages specified"
    fi

    if [[ -z "${OS_ID:-}" ]]; then
        source_os_release
    fi

    pkg_cache_refresh

    case "$OS_ID" in
        ubuntu | debian)
            sudo apt-get install -y "$@"
            ;;
        rocky | rhel | centos | almalinux | fedora)
            sudo dnf install -y "$@"
            ;;
        *)
            die "pkg_install: unsupported OS_ID: $OS_ID"
            ;;
    esac
}

# Register an apt or yum repository.
#   $1 — repo URL (apt: deb-line URL; yum: .repo file URL or base URL)
#   $2 — keyring URL (apt: armored GPG; yum: RPM-GPG key URL)
#   $3 — short name (used to derive the filename)
pkg_repo_add() {
    if [[ $# -lt 3 ]]; then
        die "pkg_repo_add: usage: pkg_repo_add <url> <keyring_url> <name>"
    fi

    local url="$1"
    local keyring_url="$2"
    local name="$3"

    if [[ -z "${OS_ID:-}" ]]; then
        source_os_release
    fi

    local apt_dir="${APT_SOURCES_DIR:-/etc/apt/sources.list.d}"
    local yum_dir="${YUM_REPOS_DIR:-/etc/yum.repos.d}"

    case "$OS_ID" in
        ubuntu | debian)
            local keyring_path="/usr/share/keyrings/${name}.gpg"
            local list_path="${apt_dir}/${name}.list"
            # Fetch keyring separately: a sourced library can't set -o pipefail,
            # so curl|gpg would silently swallow a curl failure and write an
            # empty keyring. Fail fast instead.
            local key_bytes
            key_bytes=$(curl -fsSL "$keyring_url") ||
                die "pkg_repo_add: failed to fetch keyring: $keyring_url"
            printf '%s' "$key_bytes" | sudo gpg --dearmor -o "$keyring_path"
            printf 'deb [signed-by=%s] %s\n' "$keyring_path" "$url" |
                sudo tee "$list_path" >/dev/null
            ;;
        rocky | rhel | centos | almalinux | fedora)
            local repo_path="${yum_dir}/${name}.repo"
            sudo curl -fsSL -o "$repo_path" "$url"
            sudo rpm --import "$keyring_url"
            ;;
        *)
            die "pkg_repo_add: unsupported OS_ID: $OS_ID"
            ;;
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

# On RHEL-family systems, ensure the EPEL repository is enabled.
# Several distro-layer prereqs (direnv most notably) live in EPEL rather
# than base — a fresh Rocky/RHEL install has no `direnv` package until
# EPEL is added. Noop on Debian-family. Honors DRY_RUN.
pkg_ensure_epel() {
    if [[ -z "${OS_ID:-}" ]]; then
        source_os_release
    fi

    case "$OS_ID" in
        rocky | rhel | centos | almalinux)
            if rpm -q epel-release >/dev/null 2>&1; then
                log_platform "epel-release already installed"
            elif [[ "${DRY_RUN:-0}" -eq 1 ]]; then
                log_platform "[dry-run] would dnf install -y epel-release"
                log_platform "[dry-run] would dnf config-manager --set-enabled crb"
                return 0
            else
                log_platform "enabling EPEL repository via epel-release"
                sudo dnf install -y epel-release
            fi
            # Most EPEL userspace packages (direnv among them) depend on
            # CRB (CodeReady Builder; disabled by default on Rocky/RHEL).
            log_platform "ensuring CRB repository is enabled"
            sudo dnf config-manager --set-enabled crb
            ;;
        *)
            return 0
            ;;
    esac
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
# Installs native build deps (pkg-config, openssl dev headers, C compiler)
# via pkg_install, then ensures a modern Rust toolchain through rustup
# (distro cargo on Ubuntu 24.04 / Rocky 9 is too old — see
# ensure_rust_toolchain), and finally invokes `cargo install rbw --locked`.
install_rbw() {
    local cargo_bindir="${HOME}/.cargo/bin"

    if command -v rbw >/dev/null 2>&1; then
        log_platform "rbw already installed at $(command -v rbw)"
        return 0
    fi

    if [[ -z "${OS_ID:-}" ]]; then
        source_os_release
    fi

    local -a build_deps
    case "$OS_ID" in
        ubuntu | debian)
            build_deps=(pkg-config libssl-dev build-essential)
            ;;
        rocky | rhel | centos | almalinux | fedora)
            build_deps=(pkg-config openssl-devel gcc)
            ;;
        *)
            die "install_rbw: unsupported OS_ID: $OS_ID"
            ;;
    esac

    if [[ "${DRY_RUN:-0}" -eq 1 ]]; then
        log_platform "[dry-run] would pkg_install rbw build deps: ${build_deps[*]}"
        log_platform "[dry-run] would ensure rust toolchain via rustup"
        log_platform "[dry-run] would cargo install rbw --locked into ${cargo_bindir}"
        return 0
    fi

    log_platform "installing rbw build deps: ${build_deps[*]}"
    pkg_install "${build_deps[@]}"

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
