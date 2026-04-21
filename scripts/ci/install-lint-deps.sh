#!/usr/bin/env bash
# scripts/ci/install-lint-deps.sh — install shellcheck + shfmt for the lint job.
#
# Invoked by .github/workflows/ci.yml (lint job). Keep this idempotent —
# the cache action may or may not have populated ~/.cache/shellcheck.
set -euo pipefail

sudo apt-get update -yq
sudo apt-get install -yq shellcheck shfmt

shellcheck --version
shfmt --version
