# beget — build targets (additional targets will be added in issue #7)

SHELL := /bin/bash

.PHONY: help bootstrap-test-deps lint test-unit

help:
	@echo "beget — available targets:"
	@echo "  bootstrap-test-deps  initialize the bats-core git submodule"
	@echo "  lint                 run shellcheck on lib/*.sh"
	@echo "  test-unit            run bats-core unit tests"

# Ensure the bats-core submodule is checked out before running the test suite.
bootstrap-test-deps:
	git submodule update --init --recursive tests/bats

lint:
	shellcheck lib/*.sh

test-unit: bootstrap-test-deps
	tests/bats/bin/bats tests/unit
