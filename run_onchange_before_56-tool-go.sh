#!/usr/bin/env bash
# run_onchange_before_56-tool-go.sh — install the Go toolchain from
# golang.org's official tarball and, once Go is usable, install shfmt
# via `go install`.
#
# Why Go here and not via apt: we want a pinned upstream version that's
# independent of the host distro's release cadence. Ubuntu LTS tends to
# trail by 2+ minor versions, which matters when Go modules pinned in
# other repos require a newer toolchain.
#
# Install layout:
#   /usr/local/go/           → untarred toolchain (requires sudo)
#   /usr/local/go/bin/go     → in PATH via share/env.d (out-of-scope)
#   ~/go/bin/shfmt           → user-level Go binaries (GOBIN default)
#
# Two-phase: (1) fetch+verify+untar Go if version mismatch, (2) if Go is
# available, `go install shfmt`. Phase 2 is skippable if the user is
# offline mid-bootstrap (first phase still lands the toolchain).
#
# Test seams (env-var overrides):
#   BEGET_CURL             — curl
#   BEGET_SHA256SUM        — sha256sum
#   BEGET_SUDO             — sudo (empty/env for tests → no privilege)
#   BEGET_GO_VERSION       — 1.22.3
#   BEGET_GO_URL           — tarball URL
#   BEGET_GO_SHA256        — pinned checksum
#   BEGET_GO_ROOT          — /usr/local/go
#   BEGET_GO_USER_BIN      — $HOME/go/bin
#   BEGET_GO_DRY_RUN       — "1" to iterate without curl/tar/go-install
#   BEGET_GO_SKIP_SHFMT    — "1" to skip phase 2 (phase-1-only)

set -euo pipefail

BEGET_CURL="${BEGET_CURL:-curl}"
BEGET_SHA256SUM="${BEGET_SHA256SUM:-sha256sum}"
BEGET_SUDO="${BEGET_SUDO:-sudo}"
BEGET_GO_VERSION="${BEGET_GO_VERSION:-1.22.3}"
BEGET_GO_URL="${BEGET_GO_URL:-https://go.dev/dl/go${BEGET_GO_VERSION}.linux-amd64.tar.gz}"
BEGET_GO_SHA256="${BEGET_GO_SHA256:-0000000000000000000000000000000000000000000000000000000000000001}"
BEGET_GO_ROOT="${BEGET_GO_ROOT:-/usr/local/go}"
BEGET_GO_USER_BIN="${BEGET_GO_USER_BIN:-${HOME}/go/bin}"

# Phase 1: install or replace the Go toolchain.
go_version_matches() {
    local go_bin="${BEGET_GO_ROOT}/bin/go"
    [[ -x "$go_bin" ]] || return 1
    local out
    out=$("$go_bin" version 2>/dev/null || printf '')
    [[ "$out" == *"go${BEGET_GO_VERSION}"* ]]
}

install_go() {
    if go_version_matches; then
        printf 'tool-go: go%s already installed, skipping toolchain fetch\n' \
            "$BEGET_GO_VERSION" >&2
        return 0
    fi

    if [[ "${BEGET_GO_DRY_RUN:-}" == "1" ]]; then
        printf 'tool-go: DRY-RUN would fetch %s\n' "$BEGET_GO_URL" >&2
        return 0
    fi

    local tmp
    tmp="$(mktemp -d)"
    local artifact="${tmp}/go.tar.gz"

    if ! "$BEGET_CURL" -fsSL -o "$artifact" "$BEGET_GO_URL"; then
        printf 'tool-go: failed to fetch %s\n' "$BEGET_GO_URL" >&2
        rm -rf "$tmp"
        return 1
    fi

    local actual_sha
    actual_sha=$("$BEGET_SHA256SUM" "$artifact" | awk '{print $1}')
    if [[ "$actual_sha" != "$BEGET_GO_SHA256" ]]; then
        printf 'tool-go: checksum mismatch (want=%s got=%s)\n' \
            "$BEGET_GO_SHA256" "$actual_sha" >&2
        rm -rf "$tmp"
        return 1
    fi

    # Wipe the existing Go install tree atomically (tar will replace, but
    # stale files from a larger old version could linger).
    "$BEGET_SUDO" rm -rf "$BEGET_GO_ROOT"
    "$BEGET_SUDO" install -d -m 0755 "$(dirname "$BEGET_GO_ROOT")"
    "$BEGET_SUDO" tar -C "$(dirname "$BEGET_GO_ROOT")" -xzf "$artifact"
    rm -rf "$tmp"
    printf 'tool-go: installed go%s at %s\n' \
        "$BEGET_GO_VERSION" "$BEGET_GO_ROOT" >&2
}

# Phase 2: install shfmt with the now-usable Go toolchain.
install_shfmt() {
    if [[ "${BEGET_GO_SKIP_SHFMT:-}" == "1" ]]; then
        printf 'tool-go: BEGET_GO_SKIP_SHFMT=1, skipping shfmt\n' >&2
        return 0
    fi

    local go_bin="${BEGET_GO_ROOT}/bin/go"
    if [[ ! -x "$go_bin" ]]; then
        printf 'tool-go: %s not executable, cannot install shfmt\n' \
            "$go_bin" >&2
        return 1
    fi

    if [[ -x "${BEGET_GO_USER_BIN}/shfmt" ]]; then
        printf 'tool-go: shfmt present at %s, skipping\n' \
            "${BEGET_GO_USER_BIN}/shfmt" >&2
        return 0
    fi

    if [[ "${BEGET_GO_DRY_RUN:-}" == "1" ]]; then
        printf 'tool-go: DRY-RUN would run go install mvdan.cc/sh/v3/cmd/shfmt@latest\n' >&2
        return 0
    fi

    GOBIN="$BEGET_GO_USER_BIN" "$go_bin" install mvdan.cc/sh/v3/cmd/shfmt@latest
    printf 'tool-go: installed shfmt to %s\n' "$BEGET_GO_USER_BIN" >&2
}

main() {
    install_go || return 1
    install_shfmt || return 1
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
