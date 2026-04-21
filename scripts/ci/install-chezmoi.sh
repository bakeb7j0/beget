#!/usr/bin/env bash
# scripts/ci/install-chezmoi.sh — install chezmoi for the template-render job.
#
# Uses the upstream install.sh which is the canonical install path. We pin
# to a known good version to make the CI deterministic. Binary lands in
# /usr/local/bin and is ready for `chezmoi execute-template`.
set -euo pipefail

CHEZMOI_VERSION="${CHEZMOI_VERSION:-v2.55.0}"
sh -c "$(curl -fsLS get.chezmoi.io)" -- -b /usr/local/bin -t "$CHEZMOI_VERSION"

chezmoi --version
