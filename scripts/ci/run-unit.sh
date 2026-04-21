#!/usr/bin/env bash
# scripts/ci/run-unit.sh — run bats unit tests, emitting JUnit XML to
# tests/results/report.xml for CI artifact upload.
#
# install-unit-deps.sh already initialized the tests/bats submodule. We pass
# `--report-formatter junit --output tests/results` so bats writes the XML to
# a file (and still prints TAP to stdout for humans). The older `--formatter
# junit` flag sends JUnit to stdout instead, which breaks artifact upload.
set -euo pipefail

mkdir -p tests/results

if tests/bats/bin/bats --help 2>&1 | grep -q -- '--report-formatter'; then
    exec tests/bats/bin/bats --report-formatter junit --output tests/results tests/unit
fi

exec tests/bats/bin/bats tests/unit
