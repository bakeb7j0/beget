# beget — build targets
#
# Core targets (issue #7): help, lint, apply-dry, apply, verify.
# Test-related targets from issue #5 retained for continuity.

SHELL := /bin/bash

.PHONY: help bootstrap-test-deps lint apply-dry apply verify test-unit test-integration

help:
	@echo "beget — available targets:"
	@echo "  help                 show this message (default)"
	@echo "  lint                 run shellcheck on install.sh, lib/*.sh, run_onchange_*"
	@echo "  apply-dry            chezmoi apply --dry-run --verbose"
	@echo "  apply                chezmoi apply --verbose"
	@echo "  verify               chezmoi verify (reports drift)"
	@echo "  bootstrap-test-deps  initialize the bats-core git submodule"
	@echo "  test-unit            run bats-core unit tests"
	@echo "  test-integration     run shellcheck, shfmt, chezmoi-render, header-comments (IT-01..IT-03,IT-09)"

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

bootstrap-test-deps:
	git submodule update --init --recursive tests/bats

test-unit: bootstrap-test-deps
	tests/bats/bin/bats tests/unit

# ---- Integration tests (IT-01, IT-02, IT-03, IT-09) -------------------------
# Runs each tests/integration/*.sh in turn. A failure in any one stops the
# tier with a non-zero exit so CI surfaces the first offender clearly.
test-integration:
	@set -euo pipefail; \
	for s in tests/integration/shellcheck.sh tests/integration/shfmt.sh \
	          tests/integration/chezmoi-render.sh tests/integration/header-comments.sh; do \
	    if [[ ! -x "$$s" ]]; then echo "MISSING: $$s" >&2; exit 1; fi; \
	    echo "==> $$s"; \
	    "$$s"; \
	done
