#!/usr/bin/env bash
# scripts/ci/run-unit.sh — run bats unit tests, emitting JUnit XML when
# supported by the vendored bats version.
#
# install-unit-deps.sh already initialized the tests/bats submodule. The
# `make test-unit` target only wraps the same `bats tests/unit` call plus a
# `bootstrap-test-deps` step; we intentionally invoke bats directly so we
# can pass `--formatter junit` when available for artifact upload.
set -euo pipefail

mkdir -p tests/results

if tests/bats/bin/bats --help 2>&1 | grep -q -- '--formatter'; then
    exec tests/bats/bin/bats --formatter junit --output tests/results tests/unit
fi

exec tests/bats/bin/bats tests/unit
