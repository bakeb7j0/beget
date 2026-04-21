#!/usr/bin/env bash
# run_onchange_before_51-tool-shell-installers.sh — install tools whose
# upstreams publish a curl-pipe-bash shell installer at a stable URL.
#
# These are tools that manage their own versions in a user-owned tree:
#   * rustup  → $HOME/.cargo, $HOME/.rustup        (manages rustc/cargo toolchain)
#   * bun     → $HOME/.bun                          (bun JS runtime)
#   * nvm     → $HOME/.nvm                          (node version manager)
#
# We run the installer once when the marker directory is absent; subsequent
# runs short-circuit. The installers themselves handle upgrade via their
# own subcommands (rustup self update, bun upgrade, nvm install-latest-npm).
# That's a deliberate seam: beget's job is bootstrap, not lifecycle.
#
# Security posture: curl-pipe-bash inherits the upstream's trust model.
# We bound the risk by (a) only installing when missing, (b) logging the
# URL, (c) allowing replacement via env var for offline/private mirrors.
# The list of URLs is short and audited; bumping one triggers re-install
# via chezmoi's run_onchange hash.
#
# Test seams (env-var overrides):
#   BEGET_SHELL_INSTALLERS_DRY_RUN   — "1" to iterate without curl-exec
#   BEGET_CURL                       — curl (shared with 50-)
#   BEGET_HOME                       — $HOME (redirect install targets)
#   BEGET_RUSTUP_URL, BEGET_BUN_URL, BEGET_NVM_URL
#                                    — override installer endpoints

set -euo pipefail

BEGET_CURL="${BEGET_CURL:-curl}"
BEGET_HOME="${BEGET_HOME:-$HOME}"

BEGET_RUSTUP_URL="${BEGET_RUSTUP_URL:-https://sh.rustup.rs}"
BEGET_BUN_URL="${BEGET_BUN_URL:-https://bun.sh/install}"
BEGET_NVM_URL="${BEGET_NVM_URL:-https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.7/install.sh}"

# Table format: NAME|MARKER_DIR|URL|INSTALLER_ARGS
# MARKER_DIR is the directory whose presence means "already installed".
# INSTALLER_ARGS are passed verbatim to the downloaded script via bash -s.
beget_shell_installer_table() {
    printf '%s\n' \
        "rustup|${BEGET_HOME}/.cargo|${BEGET_RUSTUP_URL}|-y --default-toolchain stable" \
        "bun|${BEGET_HOME}/.bun|${BEGET_BUN_URL}|" \
        "nvm|${BEGET_HOME}/.nvm|${BEGET_NVM_URL}|"
}

run_shell_installer() {
    local name="$1" marker="$2" url="$3" args="$4"

    if [[ -d "$marker" ]]; then
        printf 'shell-installers: %s already present at %s, skipping\n' \
            "$name" "$marker" >&2
        return 0
    fi

    if [[ "${BEGET_SHELL_INSTALLERS_DRY_RUN:-}" == "1" ]]; then
        printf 'shell-installers: DRY-RUN would install %s from %s (args=%s)\n' \
            "$name" "$url" "$args" >&2
        return 0
    fi

    printf 'shell-installers: installing %s from %s\n' "$name" "$url" >&2
    # shellcheck disable=SC2086  # intentional word-splitting of args
    if ! "$BEGET_CURL" -fsSL "$url" | bash -s -- $args; then
        printf 'shell-installers: failed to install %s\n' "$name" >&2
        return 1
    fi
}

main() {
    local failures=0
    local name marker url args
    while IFS='|' read -r name marker url args; do
        [[ -z "${name:-}" || "${name:0:1}" == "#" ]] && continue
        if ! run_shell_installer "$name" "$marker" "$url" "$args"; then
            failures=$((failures + 1))
        fi
    done < <(beget_shell_installer_table)

    if [[ $failures -gt 0 ]]; then
        printf 'shell-installers: %d installer(s) failed\n' "$failures" >&2
        return 1
    fi
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
