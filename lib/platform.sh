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
#
# Test seams (env-var overrides, default shown):
#   OS_RELEASE_FILE  — /etc/os-release
#   APT_SOURCES_DIR  — /etc/apt/sources.list.d
#   YUM_REPOS_DIR    — /etc/yum.repos.d

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

# Install one or more packages using the native package manager.
# Dispatches based on OS_ID (populated by source_os_release).
pkg_install() {
    if [[ $# -eq 0 ]]; then
        die "pkg_install: no packages specified"
    fi

    if [[ -z "${OS_ID:-}" ]]; then
        source_os_release
    fi

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
