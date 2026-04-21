#!/usr/bin/env bash
# run_onchange_before_53-tool-uv.sh — install CLIs via `uv tool install`.
#
# Why uv (not pipx) for these tools: uv's resolver handles heavy scientific
# dep trees (dvc pulls in ~80 packages) faster than pip and deduplicates
# wheels across tool venvs via its global cache. We use `uv tool install`
# which is pipx-shaped (isolated venv + PATH shim) but backed by uv.
#
# Tools (1, for now): dvc.
# The one-tool-per-script-family pattern (51=shell, 52=pipx, 53=uv) keeps
# failure modes segregated: a broken uv install doesn't mask a broken pipx
# install in logs, and each script can be re-run independently.
#
# Idempotency: `uv tool list` enumerates installed tools; skip if present.
#
# Test seams (env-var overrides):
#   BEGET_UV        — uv
#   BEGET_UV_DRY_RUN — "1" to iterate without install calls

set -euo pipefail

BEGET_UV="${BEGET_UV:-uv}"

beget_uv_packages() {
    printf '%s\n' dvc
}

uv_has_package() {
    local pkg="$1"
    # `uv tool list` prints one tool per line as "<name> v<ver>".
    "$BEGET_UV" tool list 2>/dev/null |
        awk '{print $1}' |
        grep -Fxq "$pkg"
}

install_uv_package() {
    local pkg="$1"

    if uv_has_package "$pkg"; then
        printf 'tool-uv: %s already installed, skipping\n' "$pkg" >&2
        return 0
    fi

    if [[ "${BEGET_UV_DRY_RUN:-}" == "1" ]]; then
        printf 'tool-uv: DRY-RUN would install %s\n' "$pkg" >&2
        return 0
    fi

    printf 'tool-uv: installing %s\n' "$pkg" >&2
    if ! "$BEGET_UV" tool install "$pkg"; then
        printf 'tool-uv: failed to install %s\n' "$pkg" >&2
        return 1
    fi
}

main() {
    if ! command -v "$BEGET_UV" >/dev/null 2>&1; then
        printf 'tool-uv: %s not found on PATH; install uv first\n' \
            "$BEGET_UV" >&2
        return 1
    fi

    local failures=0
    local pkg
    while IFS= read -r pkg; do
        [[ -z "$pkg" || "${pkg:0:1}" == "#" ]] && continue
        if ! install_uv_package "$pkg"; then
            failures=$((failures + 1))
        fi
    done < <(beget_uv_packages)

    if [[ $failures -gt 0 ]]; then
        printf 'tool-uv: %d package(s) failed\n' "$failures" >&2
        return 1
    fi
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
