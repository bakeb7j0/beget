#!/usr/bin/env bash
# ~/.bashrc.d/50-wrappers.sh — managed by chezmoi via beget
#
# Lazy secret materialization + tool wrappers.
#
# Sourced by ~/.bashrc via the drop-in loader (10-common.sh already set up
# PATH and hooks). Safe to re-source — all function definitions are
# idempotent and no top-level side effects fire.
#
# Public surface:
#   secret VAR [ITEM]          Lazily populate $VAR via `rbw get`. ITEM
#                              overrides the default item name derivation.
#                              Sets VAR in the caller's shell. Returns 0 on
#                              success, 1 on missing-item / rbw failure.
#   secret_get ITEM            Print the secret to stdout without mutating
#                              the env. Returns 0 on success, 1 on failure.
#   _secret_file_from_var VAR  Convert an env-var name (GITHUB_PAT) into its
#                              canonical rbw item name (github-pat). Echoes
#                              on stdout.
#   gh / glab / bao            Wrappers that materialize GITHUB_PAT,
#                              GITLAB_TOKEN, BAO_TOKEN respectively before
#                              dispatching to the real binary. Failure to
#                              materialize stops the invocation (R-16).
#
# Test seams (env-var overrides):
#   BEGET_RBW_CMD       name of the rbw binary (default: rbw).
#   BEGET_WARN          redirect warnings (default: stderr).
#
# References: R-13, R-14, R-15, R-16 in docs/beget-devspec.md.

# ---- Name conversion (R-15) --------------------------------------------------
# Lowercase + underscores-to-dashes. Example: GITHUB_PAT -> github-pat.
# Kept as _-prefixed because callers should not depend on this directly.
_secret_file_from_var() {
    local name="${1:-}"
    if [[ -z "$name" ]]; then
        return 1
    fi
    # bash 4+ parameter expansion: case-lower, tr-style replace.
    local lower="${name,,}"
    printf '%s' "${lower//_/-}"
}

# ---- Warning helper ----------------------------------------------------------
# Routes via BEGET_WARN when set so tests can capture warnings without
# colliding with bats' own stderr handling.
_secret_warn() {
    if [[ -n "${BEGET_WARN:-}" ]]; then
        printf '%s\n' "$*" >>"$BEGET_WARN"
    else
        printf 'secret: %s\n' "$*" >&2
    fi
}

# ---- rbw invocation seam -----------------------------------------------------
# Wraps rbw so tests can substitute a shim without touching PATH. Honors
# BEGET_RBW_CMD (default: `rbw`).
_secret_rbw_get() {
    local item="$1"
    local cmd="${BEGET_RBW_CMD:-rbw}"
    "$cmd" get "$item"
}

# ---- secret (R-13) -----------------------------------------------------------
# Lazily populate an env var. If the var already has a non-empty value, do
# nothing (idempotency). Otherwise, look up the item name, call rbw, and
# export into the caller's shell.
#
# Usage:
#   secret GITHUB_PAT             item name derives as github-pat
#   secret GITLAB_TOKEN analogic-gitlab-token
secret() {
    local var="${1:-}"
    local item="${2:-}"

    if [[ -z "$var" ]]; then
        _secret_warn "usage: secret VAR [ITEM]"
        return 1
    fi

    # R-13: already populated? Skip.
    if [[ -n "${!var:-}" ]]; then
        return 0
    fi

    if [[ -z "$item" ]]; then
        item="$(_secret_file_from_var "$var")"
    fi

    local value
    if ! value="$(_secret_rbw_get "$item")" || [[ -z "$value" ]]; then
        _secret_warn "rbw get '$item' failed (for \$$var)"
        return 1
    fi

    # Export so subprocesses see it. Caller is responsible for scope.
    export "$var=$value"
    return 0
}

# ---- secret_get (R-14) -------------------------------------------------------
# Retrieve a secret and print to stdout. Does NOT export or otherwise mutate
# the caller's env. Accepts the rbw item name directly (contrast with
# `secret`, which takes an env-var name). This lets .envrc use the idiomatic
# `export VAR=$(secret_get <context>-<name>)` form (R-29).
secret_get() {
    local item="${1:-}"
    if [[ -z "$item" ]]; then
        _secret_warn "usage: secret_get ITEM"
        return 1
    fi

    local value
    if ! value="$(_secret_rbw_get "$item")" || [[ -z "$value" ]]; then
        _secret_warn "rbw get '$item' failed"
        return 1
    fi

    printf '%s' "$value"
    return 0
}

# ---- Tool wrappers (R-16) ----------------------------------------------------
# Each wrapper materializes the tool's auth secret (if empty) and dispatches
# to the real binary via `command`. Materialization failure returns non-zero
# WITHOUT running the tool, so broken auth can never produce a stale call.

gh() {
    secret GITHUB_PAT || return 1
    command gh "$@"
}

glab() {
    secret GITLAB_TOKEN || return 1
    command glab "$@"
}

bao() {
    secret BAO_TOKEN || return 1
    command bao "$@"
}
