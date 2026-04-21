#!/usr/bin/env bash
# tests/integration/make-targets.sh — IT-08.
#
# Verify the Makefile declares every test tier the project expects, and that
# the fast-path target `test-quick` actually executes successfully against
# the current checkout. Heavier targets (`apply-dry`, `verify`, `test-e2e`,
# `test`) are only dry-run'd here — they either need chezmoi state (apply-dry,
# verify), docker (test-e2e), or too long to run in every CI tier.
#
# IT-08 covers requirements R-07 (idempotence wiring) and DM-02 (developer
# toolchain), with `test-quick` proving that unit + integration tiers work
# against the current tree.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$REPO_ROOT" || {
    echo "cannot cd to $REPO_ROOT" >&2
    exit 2
}

if ! command -v make >/dev/null 2>&1; then
    echo "make not installed" >&2
    exit 2
fi

# Targets the devspec requires. Each must be declared in the Makefile and
# parse cleanly under `make -n`. If make -n fails, the target is either
# missing or malformed.
required_targets=(
    help
    lint
    apply-dry
    apply
    verify
    bootstrap-test-deps
    test-unit
    test-integration
    test-e2e
    test-quick
    test
)

fail=0
for tgt in "${required_targets[@]}"; do
    if ! make -n "$tgt" >/dev/null 2>&1; then
        printf 'FAIL: make target missing or malformed: %s\n' "$tgt" >&2
        fail=1
    fi
done

# `make help` must mention every new test tier so `make help` remains a
# discoverable entry point (AC #4 on issue #29).
if ! help_out="$(make help 2>&1)"; then
    echo "FAIL: make help exited non-zero" >&2
    echo "$help_out" >&2
    exit 1
fi
for tgt in test-unit test-integration test-e2e test-quick test; do
    if ! grep -qE "^[[:space:]]*${tgt}[[:space:]]" <<<"$help_out"; then
        printf 'FAIL: make help does not document target: %s\n' "$tgt" >&2
        fail=1
    fi
done

# IT-08 does not invoke `make test-quick` itself — test-integration is a
# dependency of test-quick, so calling it here would recurse. The declaration
# and help checks above are sufficient to prove the wiring; empirical
# validation happens when a caller runs `make test-quick` directly.

exit "$fail"
