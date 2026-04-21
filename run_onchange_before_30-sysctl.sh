#!/usr/bin/env bash
# run_onchange_before_30-sysctl.sh — install and activate system-level sysctl
# tweaks from share/sysctl.d/.
#
# For each .conf file in our shipped directory, copy it to /etc/sysctl.d/
# (preserving the filename), then run `sysctl --system` once to reload all
# drop-ins.
#
# Idempotency: install -T overwrites byte-for-byte; `sysctl --system` is safe
# to re-invoke.
#
# The chezmoi include hashes below cause this script to re-run when the
# sysctl.d/ files change:
#   10-map-count.conf:         {{ include "share/sysctl.d/10-map-count.conf" | sha256sum }}
#   60-carbonyl-userns.conf:   {{ include "share/sysctl.d/60-carbonyl-userns.conf" | sha256sum }}
#
# Test seams (env-var overrides, default shown):
#   BEGET_SYSCTL_SRC_DIR  — $HOME/.local/share/beget/sysctl.d (prod path)
#   BEGET_SYSCTL_DEST_DIR — /etc/sysctl.d
#   BEGET_SUDO            — sudo
#   BEGET_SYSCTL          — sysctl
#   BEGET_SKIP_RELOAD     — "1" to skip `sysctl --system`

set -euo pipefail

BEGET_SYSCTL_SRC_DIR="${BEGET_SYSCTL_SRC_DIR:-${HOME}/.local/share/beget/sysctl.d}"
BEGET_SYSCTL_DEST_DIR="${BEGET_SYSCTL_DEST_DIR:-/etc/sysctl.d}"
BEGET_SUDO="${BEGET_SUDO:-sudo}"
BEGET_SYSCTL="${BEGET_SYSCTL:-sysctl}"

install_conf() {
    local src="$1"
    local name
    name=$(basename "$src")
    local dest="${BEGET_SYSCTL_DEST_DIR}/${name}"
    "$BEGET_SUDO" install -m 0644 -T "$src" "$dest"
    printf 'run_onchange_before_30-sysctl: installed %s\n' "$name" >&2
}

main() {
    if [[ ! -d "$BEGET_SYSCTL_SRC_DIR" ]]; then
        printf 'run_onchange_before_30-sysctl: source dir not found: %s\n' \
            "$BEGET_SYSCTL_SRC_DIR" >&2
        return 1
    fi

    # Ensure destination dir exists (it always does in production; test seam
    # covers cases where BEGET_SYSCTL_DEST_DIR points to a tmpdir).
    "$BEGET_SUDO" install -d -m 0755 "$BEGET_SYSCTL_DEST_DIR"

    local installed=0
    shopt -s nullglob
    local f
    for f in "$BEGET_SYSCTL_SRC_DIR"/*.conf; do
        install_conf "$f"
        installed=$((installed + 1))
    done
    shopt -u nullglob

    if [[ $installed -eq 0 ]]; then
        printf 'run_onchange_before_30-sysctl: no .conf files found in %s\n' \
            "$BEGET_SYSCTL_SRC_DIR" >&2
        return 0
    fi

    if [[ "${BEGET_SKIP_RELOAD:-}" != "1" ]]; then
        "$BEGET_SUDO" "$BEGET_SYSCTL" --system
    fi
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
