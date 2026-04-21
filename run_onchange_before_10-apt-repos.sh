#!/usr/bin/env bash
# run_onchange_before_10-apt-repos.sh — register third-party APT repositories.
#
# Runs before the package-install hook (prefix 20) so that repo definitions
# exist by the time `apt-get install` is invoked. Covers 10+ user-scoped repos
# that ship proprietary / upstream packages not in the Ubuntu archive.
#
# Per repo, we:
#   1. Download the GPG keyring (armored) to a temp file.
#   2. Dearmor it and place the binary keyring under /etc/apt/keyrings/<name>.gpg.
#   3. Emit a single-line sources.list.d file signed with that keyring.
# After all repos are registered we run `apt update` ONCE to pick up indices.
#
# Fail-clean semantics: if ANY keyring fetch returns 404 (or any non-2xx), we
# abort BEFORE writing the sources.list.d file for that repo. Partial state is
# not persisted — the .list file is the trigger for apt to trust the repo, so
# skipping it leaves the system in its prior working state for that repo.
#
# Idempotency: `install -m 0644 -T` overwrites existing keyrings and list
# files byte-for-byte. `apt update` is harmless to re-run.
#
# Test seams (env-var overrides, default shown):
#   BEGET_APT_KEYRINGS_DIR   — /etc/apt/keyrings
#   BEGET_APT_SOURCES_DIR    — /etc/apt/sources.list.d
#   BEGET_APT_DIST           — auto-detected from /etc/os-release (e.g. noble)
#   BEGET_CURL               — curl
#   BEGET_APT_UPDATE         — "sudo apt-get update"
#   BEGET_SUDO               — sudo (tests swap in a recording stub)
#   BEGET_SKIP_APT_UPDATE    — set to "1" to skip the final apt update
#
# The `main` function is only invoked when the script is executed directly;
# when sourced (bats tests) it exposes helpers without side effects.

set -euo pipefail

BEGET_APT_KEYRINGS_DIR="${BEGET_APT_KEYRINGS_DIR:-/etc/apt/keyrings}"
BEGET_APT_SOURCES_DIR="${BEGET_APT_SOURCES_DIR:-/etc/apt/sources.list.d}"
BEGET_CURL="${BEGET_CURL:-curl}"
BEGET_SUDO="${BEGET_SUDO:-sudo}"
BEGET_APT_UPDATE="${BEGET_APT_UPDATE:-${BEGET_SUDO} apt-get update}"

# Detect the Ubuntu release codename (noble, jammy, ...) unless overridden.
detect_dist() {
    if [[ -n "${BEGET_APT_DIST:-}" ]]; then
        printf '%s' "$BEGET_APT_DIST"
        return 0
    fi
    local os_release="${OS_RELEASE_FILE:-/etc/os-release}"
    if [[ -r "$os_release" ]]; then
        local codename
        # shellcheck disable=SC1090
        codename=$(. "$os_release" && printf '%s' "${UBUNTU_CODENAME:-${VERSION_CODENAME:-}}")
        if [[ -n "$codename" ]]; then
            printf '%s' "$codename"
            return 0
        fi
    fi
    # Safe fallback so the helper never emits an empty dist in a sources line.
    printf 'stable'
}

# Download the keyring at $1, dearmor it, install atomically to $2.
# Returns 0 on success; non-zero on fetch failure (caller must abort the repo).
install_keyring() {
    local keyring_url="$1"
    local dest_path="$2"
    local tmp
    tmp="$(mktemp)"
    # Using -f makes curl exit non-zero on 4xx/5xx; -sS silences progress but
    # keeps error messages; -L follows redirects.
    if ! "$BEGET_CURL" -fsSL "$keyring_url" -o "$tmp"; then
        rm -f "$tmp"
        return 1
    fi
    # gpg --dearmor is idempotent; destination is written atomically via
    # `install -m 0644 -T`. Both steps run under sudo so production paths
    # under /etc/apt/keyrings/ are writable.
    local tmp_dearmored
    tmp_dearmored="$(mktemp)"
    gpg --dearmor <"$tmp" >"$tmp_dearmored"
    "$BEGET_SUDO" install -m 0644 -T "$tmp_dearmored" "$dest_path"
    rm -f "$tmp" "$tmp_dearmored"
    return 0
}

# Emit a sources.list.d entry signed-by the named keyring. Writes
# atomically; overwrites any prior content.
write_sources_file() {
    local name="$1"
    local sources_line="$2"
    local keyring_path="$3"
    local dist
    dist=$(detect_dist)
    local dest="${BEGET_APT_SOURCES_DIR}/${name}.list"
    local tmp
    tmp="$(mktemp)"
    # %s is the fully rendered sources line; callers template the dist name in.
    local rendered="${sources_line//\{\{DIST\}\}/$dist}"
    printf 'deb [signed-by=%s] %s\n' "$keyring_path" "$rendered" >"$tmp"
    "$BEGET_SUDO" install -m 0644 -T "$tmp" "$dest"
    rm -f "$tmp"
}

# Register one repo: name, sources_line template, keyring URL.
# Sources line is the text AFTER "deb [signed-by=...] ". Substrings of
# {{DIST}} are replaced with the detected codename.
# On fetch failure, emits a warning and returns non-zero WITHOUT writing the
# sources file — callers should choose whether to abort the whole run.
register_repo() {
    local name="$1"
    local sources_line="$2"
    local keyring_url="$3"
    local keyring_path="${BEGET_APT_KEYRINGS_DIR}/${name}.gpg"

    if ! install_keyring "$keyring_url" "$keyring_path"; then
        printf 'run_onchange_before_10-apt-repos: failed to fetch keyring for %s (%s), skipping\n' \
            "$name" "$keyring_url" >&2
        return 1
    fi
    write_sources_file "$name" "$sources_line" "$keyring_path"
    printf 'run_onchange_before_10-apt-repos: registered %s\n' "$name" >&2
}

# Ensure the keyring directory exists under sudo (production path is
# owned by root).
ensure_dirs() {
    "$BEGET_SUDO" install -d -m 0755 "$BEGET_APT_KEYRINGS_DIR" "$BEGET_APT_SOURCES_DIR"
}

main() {
    ensure_dirs

    # Repo table: NAME|SOURCES_LINE|KEYRING_URL
    # SOURCES_LINE uses {{DIST}} for the Ubuntu codename. One entry per line.
    local -a repos=(
        "mozilla|https://packages.mozilla.org/apt mozilla main|https://packages.mozilla.org/apt/repo-signing-key.gpg"
        "google-chrome|https://dl.google.com/linux/chrome/deb/ stable main|https://dl.google.com/linux/linux_signing_key.pub"
        "vivaldi|https://repo.vivaldi.com/stable/deb/ stable main|https://repo.vivaldi.com/stable/linux_signing_key.pub"
        "slack|https://packagecloud.io/slacktechnologies/slack/debian/ jessie main|https://packagecloud.io/slacktechnologies/slack/gpgkey"
        "spotify|http://repository.spotify.com stable non-free|https://download.spotify.com/debian/pubkey_6224F9941A8AA6D1.gpg"
        "wezterm|https://apt.fury.io/wez/ * *|https://apt.fury.io/wez/gpg.key"
        "hashicorp|https://apt.releases.hashicorp.com {{DIST}} main|https://apt.releases.hashicorp.com/gpg"
        "vscode|https://packages.microsoft.com/repos/code stable main|https://packages.microsoft.com/keys/microsoft.asc"
        "synaptics|https://synaptics.com/sites/default/files/Ubuntu {{DIST}} main|https://synaptics.com/sites/default/files/synaptics.gpg"
        "nextcloud-devs|http://ppa.launchpad.net/nextcloud-devs/client/ubuntu {{DIST}} main|https://keyserver.ubuntu.com/pks/lookup?op=get&search=0xE0AB4EC4B5DE39A7C36249C2D67C3E6685166D1C"
        "xtradeb-apps|http://ppa.launchpad.net/xtradeb/apps/ubuntu {{DIST}} main|https://keyserver.ubuntu.com/pks/lookup?op=get&search=0x11031A9F63E8D6AFC4B58E2E62459C5CAFAB58E3"
    )

    local entry name sources keyring_url
    local failures=0
    for entry in "${repos[@]}"; do
        IFS='|' read -r name sources keyring_url <<<"$entry"
        if ! register_repo "$name" "$sources" "$keyring_url"; then
            failures=$((failures + 1))
        fi
    done

    if [[ "${BEGET_SKIP_APT_UPDATE:-}" != "1" ]]; then
        # apt update is run even if some repos failed — the surviving repos
        # must still refresh. Overall script still exits non-zero if any
        # register_repo failed, so chezmoi surfaces the error.
        $BEGET_APT_UPDATE
    fi

    if [[ $failures -gt 0 ]]; then
        printf 'run_onchange_before_10-apt-repos: %d repo(s) failed\n' "$failures" >&2
        return 1
    fi
}

# Allow sourcing for tests without side effects: only run main when executed.
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
