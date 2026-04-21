#!/usr/bin/env bash
# run_onchange_before_54-tool-claude-code.sh — install Anthropic's Claude
# Code CLI.
#
# Claude Code ships an official curl-pipe-bash installer at a stable URL.
# On Linux it places a binary at $HOME/.local/bin/claude and seeds config
# under $HOME/.claude/. Subsequent updates are managed in-process by the
# CLI itself (`claude update`), so beget's role is bootstrap only.
#
# Why its own script (separate from 51-shell-installers): the Claude Code
# installer is not a Makefile-style toolchain installer (rustup/bun/nvm
# mutate PATH-visible toolchains); it's an end-user CLI with its own
# self-update path. Separating keeps the failure log cleanly attributable
# and lets us gate it behind an env var if an air-gapped host can't reach
# the CDN.
#
# Idempotency: if $HOME/.local/bin/claude is an executable file, we skip.
# Self-updates after install are the CLI's job, not ours.
#
# Test seams (env-var overrides):
#   BEGET_CURL               — curl
#   BEGET_BIN_DIR            — $HOME/.local/bin
#   BEGET_CLAUDE_CODE_URL    — installer endpoint
#   BEGET_CLAUDE_CODE_DRY_RUN — "1" to iterate without curl-exec
#   BEGET_CLAUDE_CODE_SKIP   — "1" to skip entirely (air-gap mode)

set -euo pipefail

BEGET_CURL="${BEGET_CURL:-curl}"
BEGET_BIN_DIR="${BEGET_BIN_DIR:-${HOME}/.local/bin}"
# TODO(installer-url): https://claude.ai/install.sh is a PLACEHOLDER — the
# real Claude Code install URL must be confirmed by the beget maintainer
# against Anthropic's current documentation before shipping. A real bootstrap
# run can be forced to the correct endpoint via BEGET_CLAUDE_CODE_URL
# without touching this file.
BEGET_CLAUDE_CODE_URL="${BEGET_CLAUDE_CODE_URL:-https://claude.ai/install.sh}"

main() {
    if [[ "${BEGET_CLAUDE_CODE_SKIP:-}" == "1" ]]; then
        printf 'tool-claude-code: BEGET_CLAUDE_CODE_SKIP=1, skipping\n' >&2
        return 0
    fi

    local bin="${BEGET_BIN_DIR}/claude"
    if [[ -x "$bin" ]]; then
        printf 'tool-claude-code: %s present, skipping\n' "$bin" >&2
        return 0
    fi

    if [[ "${BEGET_CLAUDE_CODE_DRY_RUN:-}" == "1" ]]; then
        printf 'tool-claude-code: DRY-RUN would install from %s\n' \
            "$BEGET_CLAUDE_CODE_URL" >&2
        return 0
    fi

    printf 'tool-claude-code: installing from %s\n' \
        "$BEGET_CLAUDE_CODE_URL" >&2
    if ! "$BEGET_CURL" -fsSL "$BEGET_CLAUDE_CODE_URL" | bash; then
        printf 'tool-claude-code: installer failed\n' >&2
        return 1
    fi
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
