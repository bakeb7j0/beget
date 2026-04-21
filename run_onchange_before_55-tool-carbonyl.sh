#!/usr/bin/env bash
# run_onchange_before_55-tool-carbonyl.sh — install Carbonyl, the
# Chromium-in-the-terminal fork from fathyb/carbonyl.
#
# Upstream ships pre-built static Linux binaries on GitHub releases. We
# fetch the pinned tarball, verify sha256, and drop the single `carbonyl`
# binary into ~/.local/bin/. Unlike 50-tool-download-binaries, Carbonyl's
# versioning cadence is slow enough that keeping it in its own script
# makes the update signal obvious in chezmoi's re-trigger (one script
# changed → one reason).
#
# Runtime dependency: Carbonyl invokes Chromium's sandbox which requires
# unprivileged user namespaces. On workstations we enable this via the
# sysctl file share/sysctl.d/60-carbonyl-userns.conf installed by
# run_onchange_before_30-sysctl.sh. If that sysctl is not in effect,
# carbonyl will fail at runtime with a sandbox error — this script does
# NOT verify the kernel flag because sysctl/30 runs before us (numeric
# prefix ordering) and beget treats failed sysctl as fatal.
#
# Idempotency: if ~/.local/bin/carbonyl --version reports the pinned
# version, skip. Identical pattern to 50-.
#
# Test seams (env-var overrides):
#   BEGET_CURL                — curl
#   BEGET_SHA256SUM           — sha256sum
#   BEGET_BIN_DIR             — $HOME/.local/bin
#   BEGET_CARBONYL_VERSION    — 0.0.3
#   BEGET_CARBONYL_URL        — release tarball URL
#   BEGET_CARBONYL_SHA256     — pinned checksum
#   BEGET_CARBONYL_DRY_RUN    — "1" to iterate without curl-exec

set -euo pipefail

BEGET_CURL="${BEGET_CURL:-curl}"
BEGET_SHA256SUM="${BEGET_SHA256SUM:-sha256sum}"
BEGET_BIN_DIR="${BEGET_BIN_DIR:-${HOME}/.local/bin}"
BEGET_CARBONYL_VERSION="${BEGET_CARBONYL_VERSION:-0.0.3}"
BEGET_CARBONYL_URL="${BEGET_CARBONYL_URL:-https://github.com/fathyb/carbonyl/releases/download/v${BEGET_CARBONYL_VERSION}/carbonyl.x86_64-unknown-linux-gnu.tar.gz}"
# Placeholder checksum; real value is pinned at maintainer bump time.
BEGET_CARBONYL_SHA256="${BEGET_CARBONYL_SHA256:-0000000000000000000000000000000000000000000000000000000000000001}"

current_version_matches() {
    local bin="${BEGET_BIN_DIR}/carbonyl"
    [[ -x "$bin" ]] || return 1
    local out
    out=$("$bin" --version 2>/dev/null || printf '')
    [[ "$out" == *"$BEGET_CARBONYL_VERSION"* ]]
}

main() {
    install -d -m 0755 "$BEGET_BIN_DIR"

    if [[ "${BEGET_CARBONYL_DRY_RUN:-}" != "1" ]] \
       && current_version_matches; then
        printf 'tool-carbonyl: v%s already current, skipping\n' \
            "$BEGET_CARBONYL_VERSION" >&2
        return 0
    fi

    if [[ "${BEGET_CARBONYL_DRY_RUN:-}" == "1" ]]; then
        printf 'tool-carbonyl: DRY-RUN would fetch %s\n' \
            "$BEGET_CARBONYL_URL" >&2
        return 0
    fi

    local tmp
    tmp="$(mktemp -d)"
    local artifact="${tmp}/carbonyl.tar.gz"

    if ! "$BEGET_CURL" -fsSL -o "$artifact" "$BEGET_CARBONYL_URL"; then
        printf 'tool-carbonyl: failed to fetch %s\n' "$BEGET_CARBONYL_URL" >&2
        rm -rf "$tmp"
        return 1
    fi

    local actual_sha
    actual_sha=$("$BEGET_SHA256SUM" "$artifact" | awk '{print $1}')
    if [[ "$actual_sha" != "$BEGET_CARBONYL_SHA256" ]]; then
        printf 'tool-carbonyl: checksum mismatch (want=%s got=%s)\n' \
            "$BEGET_CARBONYL_SHA256" "$actual_sha" >&2
        rm -rf "$tmp"
        return 1
    fi

    tar -xzf "$artifact" -C "$tmp"
    if [[ ! -f "${tmp}/carbonyl" ]]; then
        printf 'tool-carbonyl: tarball did not contain expected binary\n' >&2
        rm -rf "$tmp"
        return 1
    fi

    install -D -m 0755 -T "${tmp}/carbonyl" "${BEGET_BIN_DIR}/carbonyl"
    rm -rf "$tmp"
    printf 'tool-carbonyl: installed v%s\n' "$BEGET_CARBONYL_VERSION" >&2
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
