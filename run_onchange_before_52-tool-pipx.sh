#!/usr/bin/env bash
# run_onchange_before_52-tool-pipx.sh — install Python CLIs into isolated
# per-tool venvs via pipx.
#
# Why pipx: the tools below are Python-authored end-user CLIs (no library
# consumption). Putting them in system Python risks dependency collisions
# with apt-shipped python3-*; putting them in a shared venv ties them to
# a single Python version. pipx spawns a venv per tool, wires a shim on
# PATH, and handles the upgrade path cleanly.
#
# Tools (4): yamllint, yt-dlp, gl-settings, kairos-contracts.
# pipx itself is assumed present (package list includes `pipx`); we fail
# fast and diagnostically if it isn't.
#
# Idempotency: `pipx list --short` output is parsed for the package name;
# if present, we skip (lifecycle upgrades happen outside beget). If absent,
# we run `pipx install NAME`. That's the user-visible chezmoi contract.
#
# Test seams (env-var overrides):
#   BEGET_PIPX        — pipx
#   BEGET_PIPX_DRY_RUN — "1" to iterate the list without install calls

set -euo pipefail

BEGET_PIPX="${BEGET_PIPX:-pipx}"

beget_pipx_packages() {
    printf '%s\n' \
        yamllint \
        yt-dlp \
        gl-settings \
        kairos-contracts
}

pipx_has_package() {
    local pkg="$1"
    # `pipx list --short` prints "<name> <version>" per line.
    "$BEGET_PIPX" list --short 2>/dev/null \
        | awk '{print $1}' \
        | grep -Fxq "$pkg"
}

install_pipx_package() {
    local pkg="$1"

    if pipx_has_package "$pkg"; then
        printf 'tool-pipx: %s already installed, skipping\n' "$pkg" >&2
        return 0
    fi

    if [[ "${BEGET_PIPX_DRY_RUN:-}" == "1" ]]; then
        printf 'tool-pipx: DRY-RUN would install %s\n' "$pkg" >&2
        return 0
    fi

    printf 'tool-pipx: installing %s\n' "$pkg" >&2
    if ! "$BEGET_PIPX" install "$pkg"; then
        printf 'tool-pipx: failed to install %s\n' "$pkg" >&2
        return 1
    fi
}

main() {
    if ! command -v "$BEGET_PIPX" >/dev/null 2>&1; then
        printf 'tool-pipx: %s not found on PATH; install pipx first\n' \
            "$BEGET_PIPX" >&2
        return 1
    fi

    local failures=0
    local pkg
    while IFS= read -r pkg; do
        [[ -z "$pkg" || "${pkg:0:1}" == "#" ]] && continue
        if ! install_pipx_package "$pkg"; then
            failures=$((failures + 1))
        fi
    done < <(beget_pipx_packages)

    if [[ $failures -gt 0 ]]; then
        printf 'tool-pipx: %d package(s) failed\n' "$failures" >&2
        return 1
    fi
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
