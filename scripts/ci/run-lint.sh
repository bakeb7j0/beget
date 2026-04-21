#!/usr/bin/env bash
# scripts/ci/run-lint.sh — execute the `lint` job's checks.
#
# Runs `make lint` (shellcheck). On this CI pipeline `make lint` already
# covers install.sh, lib/*.sh, and run_onchange_* scripts. Keep thin: any
# additional linting belongs in the Makefile, not here.
set -euo pipefail

make lint
