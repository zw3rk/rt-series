# rt-series Makefile
#
# Copyright 2026 Moritz Angermann <moritz@zw3rk.com>, zw3rk pte. ltd.
# SPDX-License-Identifier: Apache-2.0

.DEFAULT_GOAL := help

CC      ?= cc
CFLAGS  ?= -std=c11 -Wall -Wextra -Werror=vla -pedantic
BUILD   := _build

REQUIRED_DOCS := \
	README.md \
	AGENTS.md \
	CLAUDE.md \
	LICENSE \
	SPEC.md \
	PLAN.md \
	GOAL.md \
	docs/HOST-CONTRACT.md \
	docs/lanes/wave-1-closeout.md \
	docs/lanes/wave-2-rv32gc.md \
	docs/lanes/wave-3-rt32-family.md \
	docs/lanes/wave-4-rt64-family.md \
	lode/README.md \
	lode/STATE-OF-PLAY-2026-10-23.md \
	lode/ISA-TRAP-AND-ABI-MATRIX.md \
	lode/reviews/2026-10-23-astra-review-1.md \
	lode/reviews/2026-10-23-astra-review-1-dispositions.md \
	lode/reviews/2026-10-23-astra-review-2.md \
	lode/reviews/2026-10-23-astra-review-2-dispositions.md \
	tests/check_abi_invariants.c

SIBLING_REPOS := \
	../a32rt \
	../i686rt \
	../rvrt \
	../hyper-linux

.PHONY: help all build test check check-headers check-abi-invariants check-docs check-siblings status clean

##@ General

help: ## Display this help message
	@awk 'BEGIN {FS = ":.*##"; printf "\nUsage:\n  make \033[36m<target>\033[0m\n"} \
		/^[a-zA-Z0-9_-]+:.*?##/ { printf "  \033[36m%-20s\033[0m %s\n", $$1, $$2 } \
		/^##@/ { printf "\n\033[1m%s\033[0m\n", substr($$0, 5) } ' $(MAKEFILE_LIST)

all: check ## Run default umbrella verification checks

build: check-headers check-abi-invariants ## Validate shared C11 headers and frozen ABI layout invariants

##@ Verification

test: check ## Alias for check

check: check-headers check-abi-invariants check-docs ## Validate umbrella headers, frozen ABI struct layouts, and documentation presence
	@echo "rt-series: umbrella header, ABI-layout, and document presence checks passed."

check-headers: ## Compile-check shared C11 headers under strict Curated C11 flags
	@mkdir -p $(BUILD)
	$(CC) $(CFLAGS) -Iinclude -fsyntax-only include/a32host.h
	@touch $(BUILD)/headers.ok
	@echo "CHECK-HEADERS OK"

check-abi-invariants: ## Build and run compile-time/runtime frozen ABI layout & HWCAP assertions
	@mkdir -p $(BUILD)
	$(CC) $(CFLAGS) -Iinclude -o $(BUILD)/check_abi_invariants tests/check_abi_invariants.c
	$(BUILD)/check_abi_invariants

check-docs: ## Verify all required specifications, lane cards, and lode records exist and are non-empty
	@for f in $(REQUIRED_DOCS); do \
		if [ ! -s "$$f" ]; then \
			echo "MISSING OR EMPTY: $$f" >&2; \
			exit 1; \
		fi; \
	done
	@echo "CHECK-DOCS OK ($(words $(REQUIRED_DOCS)) files verified)"

check-siblings: ## Inspect git status and HEAD across existing sibling repositories
	@for d in $(SIBLING_REPOS); do \
		if [ -d "$$d/.git" ] || [ -f "$$d/.git" ]; then \
			printf "=== %-16s (%s) ===\n" "$$d" "$$(git -C "$$d" rev-parse --short HEAD 2>/dev/null)"; \
			git -C "$$d" status -sb 2>/dev/null | head -n 20; \
		else \
			printf "=== %-16s (missing) ===\n" "$$d"; \
		fi; \
	done

status: check-siblings ## Alias for check-siblings

##@ Cleanup

clean: ## Remove build artifacts
	rm -rf $(BUILD)
