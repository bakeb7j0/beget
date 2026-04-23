#!/usr/bin/env bash
# run_onchange_before_20-packages-common.sh — install role-scoped package lists.
#
# chezmoi `run_onchange_before_*` hook: chezmoi invokes this script when its
# contents change. We therefore include the hash of every list file we read
# (via the chezmoi `sha256sum` template below) so edits to any list trigger a
# re-install. The script itself is role-agnostic: it inspects BEGET_ROLE (or
# derives it from chezmoi data) and installs the matching role's packages.
#
# Roles:
#   minimal     → installs only apt-packages-minimal.list (no common)
#   server      → installs common + server
#   workstation → installs common + workstation
#   (default)   → installs common only
#
# Idempotency: the default installer delegates to `apt-get install -y` or
# `dnf install -y`, both of which are no-ops when the package is already at
# the requested version.
#
# Root access: this hook needs root to install packages. Unlike install.sh
# (which is strictly user-local post-#100), chezmoi apply is an interactive
# step the user runs knowingly, so BEGET_SUDO=sudo is safe here. Tests
# stub the installer wholesale via BEGET_PKG_INSTALL.
#
# Test seams (env-var overrides):
#   BEGET_ROLE           — role selector (default: workstation)
#   BEGET_PACKAGE_DIR    — directory containing apt-packages-*.list
#                          (default: $HOME/.local/share/beget)
#   BEGET_PKG_INSTALL    — function name to invoke (default: beget_pkg_install)
#                          override allows unit tests to capture invocations.
#   BEGET_SUDO           — sudo (production); tests typically override
#                          BEGET_PKG_INSTALL instead of mocking sudo.
#   OS_RELEASE_FILE      — os-release file path (default /etc/os-release)
#
# chezmoi injects the following hashes so this script re-runs on any list edit:
#   common:      {{ include "share/apt-packages-common.list" | sha256sum }}
#   workstation: {{ include "share/apt-packages-workstation.list" | sha256sum }}
#   server:      {{ include "share/apt-packages-server.list" | sha256sum }}
#   minimal:     {{ include "share/apt-packages-minimal.list" | sha256sum }}

set -euo pipefail

PACKAGE_DIR="${BEGET_PACKAGE_DIR:-${HOME}/.local/share/beget}"
ROLE="${BEGET_ROLE:-workstation}"
BEGET_SUDO="${BEGET_SUDO:-sudo}"

# Default installer: dispatch to apt-get or dnf based on /etc/os-release.
# This is self-contained (no dependency on lib/platform.sh) because #100
# keeps platform.sh sudo-free. Tests override via BEGET_PKG_INSTALL.
beget_pkg_install() {
    local os_release_file="${OS_RELEASE_FILE:-/etc/os-release}"
    local id=""
    if [[ -r "$os_release_file" ]]; then
        # shellcheck disable=SC1090
        id=$(. "$os_release_file" && printf '%s' "${ID:-}")
    fi
    case "$id" in
        ubuntu | debian)
            $BEGET_SUDO apt-get install -y "$@"
            ;;
        rocky | rhel | centos | almalinux | fedora)
            $BEGET_SUDO dnf install -y "$@"
            ;;
        *)
            printf 'run_onchange_before_20-packages-common: unsupported OS %s, cannot install packages\n' "${id:-unknown}" >&2
            return 1
            ;;
    esac
}

# Read a package list file and emit one package name per line, skipping blank
# lines and `#` comment lines. Leading/trailing whitespace is stripped so that
# list formatting (indentation, tabs) does not affect package names.
read_list() {
    local list_file="$1"
    # awk handles whitespace stripping and comment filtering in a single pass.
    awk '
        {
            sub(/#.*/, "")          # drop inline comments
            gsub(/^[ \t]+|[ \t]+$/, "")
            if (length($0) > 0) print
        }
    ' "$list_file"
}

# Install every package named in the given list file, if the file exists.
install_from_list() {
    local list_file="$1"
    if [[ ! -r "$list_file" ]]; then
        printf 'run_onchange_before_20-packages-common: skip missing list %s\n' "$list_file" >&2
        return 0
    fi

    local -a pkgs=()
    while IFS= read -r pkg; do
        pkgs+=("$pkg")
    done < <(read_list "$list_file")

    if [[ ${#pkgs[@]} -eq 0 ]]; then
        printf 'run_onchange_before_20-packages-common: %s is empty, nothing to install\n' "$list_file" >&2
        return 0
    fi

    local installer="${BEGET_PKG_INSTALL:-beget_pkg_install}"
    "$installer" "${pkgs[@]}"
}

main() {
    local common_list="${PACKAGE_DIR}/apt-packages-common.list"
    local role_list="${PACKAGE_DIR}/apt-packages-${ROLE}.list"

    case "$ROLE" in
        minimal)
            # minimal role gets only the survival-kit list, NOT common.
            install_from_list "${PACKAGE_DIR}/apt-packages-minimal.list"
            ;;
        workstation | server)
            install_from_list "$common_list"
            install_from_list "$role_list"
            ;;
        *)
            printf 'run_onchange_before_20-packages-common: unknown role %s, installing common only\n' "$ROLE" >&2
            install_from_list "$common_list"
            ;;
    esac
}

main "$@"
