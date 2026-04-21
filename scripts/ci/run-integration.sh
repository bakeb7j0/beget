#!/usr/bin/env bash
# scripts/ci/run-integration.sh — integration test tier (IT-01, IT-02, IT-03, IT-09).
#
# Delegates to `make test-integration`, which runs each tests/integration/*.sh
# in order: shellcheck.sh (IT-01), shfmt.sh (IT-02), chezmoi-render.sh (IT-03),
# header-comments.sh (IT-09). A failure in any one fails this job.
set -euo pipefail

make test-integration
