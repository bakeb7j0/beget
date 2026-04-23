# beget — build targets
#
# Core targets (issue #7): help, lint, apply-dry, apply, verify.
# Test targets (issue #5, #29): test-unit, test-integration, test-e2e, test, test-quick.

SHELL := /bin/bash

.PHONY: help bootstrap-test-deps lint apply-dry apply verify \
        test-unit test-integration test-e2e test test-quick

help:
	@echo "beget — available targets:"
	@echo "  help                 show this message (default)"
	@echo "  lint                 run shellcheck on install.sh, lib/*.sh, run_onchange_*"
	@echo "  apply-dry            chezmoi apply --dry-run --verbose"
	@echo "  apply                chezmoi apply --verbose"
	@echo "  verify               chezmoi verify (reports drift)"
	@echo "  bootstrap-test-deps  initialize the bats-core git submodule"
	@echo "  test-unit            run bats-core unit tests (JUnit XML → tests/results/)"
	@echo "  test-integration     run shellcheck, shfmt, chezmoi-render, header-comments (IT-01..IT-03,IT-09)"
	@echo "  test-e2e             build Docker images and run E2E suite (DISTRO=ubuntu24|rocky9; both if unset)"
	@echo "  test-quick           test-unit + test-integration (targets < 30s on workstation)"
	@echo "  test                 all three tiers: unit + integration + e2e"

# ---- Linting ----------------------------------------------------------------
# Shellcheck every bash file we own: the bootstrap entry, the sourced library,
# and any run_onchange_* scripts chezmoi will execute. Globs are expanded with
# nullglob so a currently-empty run_onchange_* set does not fail the build.
lint:
	@set -euo pipefail; \
	shopt -s nullglob; \
	files=(); \
	[[ -f install.sh ]] && files+=(install.sh); \
	files+=(lib/*.sh); \
	files+=(run_onchange_*); \
	if [[ $${#files[@]} -eq 0 ]]; then \
	    echo "lint: no files to check"; \
	    exit 0; \
	fi; \
	echo "shellcheck $${files[*]}"; \
	shellcheck "$${files[@]}"

# ---- Chezmoi wrappers -------------------------------------------------------

apply-dry:
	chezmoi apply --dry-run --verbose

apply:
	chezmoi apply --verbose

verify:
	chezmoi verify

# ---- Tests ------------------------------------------------------------------
# Every test tier writes JUnit XML to tests/results/ (gitignored). CI uploads
# this directory as a job artifact; local runs can inspect it to debug.

bootstrap-test-deps:
	git submodule update --init --recursive tests/bats

# Unit tests — bats 1.13 `--report-formatter junit --output <dir>` writes
# tests/results/report.xml; the TAP stream goes to stdout for humans. Note:
# bats's `--formatter junit` replaces stdout instead of writing a file — use
# `--report-formatter` for the artifact path.
test-unit: bootstrap-test-deps
	@mkdir -p tests/results
	tests/bats/bin/bats --report-formatter junit --output tests/results tests/unit

# ---- Integration tests (IT-01, IT-02, IT-03, IT-08, IT-09, IT-10) -----------
# Runs each tests/integration/*.sh in turn. A failure in any one stops the
# tier with a non-zero exit so CI surfaces the first offender clearly.
test-integration:
	@set -euo pipefail; \
	mkdir -p tests/results; \
	for s in tests/integration/shellcheck.sh tests/integration/shfmt.sh \
	          tests/integration/chezmoi-render.sh tests/integration/header-comments.sh \
	          tests/integration/make-targets.sh tests/integration/chezmoiignore-dispatch.sh; do \
	    if [[ ! -x "$$s" ]]; then echo "MISSING: $$s" >&2; exit 1; fi; \
	    echo "==> $$s"; \
	    "$$s"; \
	done

# ---- E2E tests --------------------------------------------------------------
# Delegates to scripts/ci/run-e2e.sh which builds the Dockerfile for a given
# distro and runs each tests/e2e/e2e-*.sh inside a fresh container. Pass
# DISTRO=ubuntu24 or DISTRO=rocky9 to target one distro; unset runs both.
test-e2e:
	@set -euo pipefail; \
	mkdir -p tests/results; \
	if [[ -n "$${DISTRO:-}" ]]; then \
	    ./scripts/ci/run-e2e.sh "$$DISTRO"; \
	else \
	    ./scripts/ci/run-e2e.sh ubuntu24; \
	    ./scripts/ci/run-e2e.sh rocky9; \
	fi

# ---- Aggregate tiers --------------------------------------------------------

test: test-unit test-integration test-e2e

test-quick: test-unit test-integration
