#!/usr/bin/env bash
# run_onchange_before_10-dnf-repos.sh — register third-party DNF repositories
# on Rocky/RHEL/Fedora. RHEL counterpart to run_onchange_before_10-apt-repos.sh.
#
# For each repo we:
#   1. Download a .repo file (or write one from a base URL) under
#      /etc/yum.repos.d/<name>.repo via `install -m 0644 -T`.
#   2. Import the RPM-GPG key via `rpm --import`, so signature checks pass.
# Finally we run `dnf makecache` so subsequent installs resolve against the
# new repos.
#
# This script is a shim in the current wave: the Dev Spec lists RHEL as a
# supported target but the third-party repo coverage is intentionally a
# superset of what is commonly available on EPEL/RPM-Fusion/HashiCorp/etc.
# Additional per-repo tables can be appended as needs arise.
#
# Idempotency: `install -T` overwrites existing files; `rpm --import` is a
# no-op on already-trusted keys; `dnf makecache` is idempotent.
#
# Test seams (env-var overrides):
#   BEGET_YUM_REPOS_DIR — /etc/yum.repos.d
#   BEGET_CURL          — curl
#   BEGET_SUDO          — sudo
#   BEGET_RPM           — rpm
#   BEGET_DNF           — dnf
#   BEGET_SKIP_MAKECACHE — "1" to skip `dnf makecache`

set -euo pipefail

BEGET_YUM_REPOS_DIR="${BEGET_YUM_REPOS_DIR:-/etc/yum.repos.d}"
BEGET_CURL="${BEGET_CURL:-curl}"
BEGET_SUDO="${BEGET_SUDO:-sudo}"
BEGET_RPM="${BEGET_RPM:-rpm}"
BEGET_DNF="${BEGET_DNF:-dnf}"

# Download a .repo file and install it atomically under $BEGET_YUM_REPOS_DIR.
install_repo_file() {
    local name="$1"
    local repo_url="$2"
    local tmp
    tmp="$(mktemp)"
    if ! "$BEGET_CURL" -fsSL "$repo_url" -o "$tmp"; then
        rm -f "$tmp"
        return 1
    fi
    "$BEGET_SUDO" install -m 0644 -T "$tmp" "${BEGET_YUM_REPOS_DIR}/${name}.repo"
    rm -f "$tmp"
}

# Trust the RPM signing key for a repo. Takes a URL or local path.
import_rpm_key() {
    local key_url="$1"
    "$BEGET_SUDO" "$BEGET_RPM" --import "$key_url"
}

register_repo() {
    local name="$1"
    local repo_url="$2"
    local key_url="$3"
    if ! install_repo_file "$name" "$repo_url"; then
        printf 'run_onchange_before_10-dnf-repos: failed to fetch %s (%s), skipping\n' \
            "$name" "$repo_url" >&2
        return 1
    fi
    import_rpm_key "$key_url"
    printf 'run_onchange_before_10-dnf-repos: registered %s\n' "$name" >&2
}

ensure_dirs() {
    "$BEGET_SUDO" install -d -m 0755 "$BEGET_YUM_REPOS_DIR"
}

main() {
    ensure_dirs

    # NAME|REPO_FILE_URL|RPM_GPG_KEY_URL
    local -a repos=(
        "hashicorp|https://rpm.releases.hashicorp.com/RHEL/hashicorp.repo|https://rpm.releases.hashicorp.com/gpg"
        "vscode|https://packages.microsoft.com/yumrepos/vscode/config.repo|https://packages.microsoft.com/keys/microsoft.asc"
        "google-chrome|http://dl.google.com/linux/chrome/rpm/stable/x86_64/google-chrome.repo|https://dl.google.com/linux/linux_signing_key.pub"
    )

    local entry name repo_url key_url
    local failures=0
    for entry in "${repos[@]}"; do
        IFS='|' read -r name repo_url key_url <<<"$entry"
        if ! register_repo "$name" "$repo_url" "$key_url"; then
            failures=$((failures + 1))
        fi
    done

    if [[ "${BEGET_SKIP_MAKECACHE:-}" != "1" ]]; then
        "$BEGET_SUDO" "$BEGET_DNF" makecache
    fi

    if [[ $failures -gt 0 ]]; then
        printf 'run_onchange_before_10-dnf-repos: %d repo(s) failed\n' "$failures" >&2
        return 1
    fi
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
