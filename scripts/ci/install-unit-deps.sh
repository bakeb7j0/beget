#!/usr/bin/env bash
# scripts/ci/install-unit-deps.sh — ensure bats is available for the unit
# job. The repo vendors bats-core as a submodule at tests/bats; we just
# need the submodule initialized (the checkout step may already have done
# this, but double-check so a fresh cache still works).
set -euo pipefail

git submodule update --init --recursive tests/bats

tests/bats/bin/bats --version
