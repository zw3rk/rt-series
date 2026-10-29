#!/bin/sh
# tests/catalogue/run_catalogue.sh — Acceptance wrapper (Wave C1).
# Execs the unified runner so lane gates stay single-sourced.
# Copyright 2026 Moritz Angermann <moritz@zw3rk.com>, zw3rk pte. ltd.
# SPDX-License-Identifier: Apache-2.0
set -eu
HERE="$(cd "$(dirname "$0")" && pwd)"
exec "$HERE/../../tools/run_catalogue.sh" "$@"
