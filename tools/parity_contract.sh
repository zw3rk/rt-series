#!/bin/sh
# tools/parity_contract.sh — Frozen Cross-Repository Parity Row & Golden Contract
#
# Sourced by `<repo>/tests/parity_suite.sh` across all 10 `rt-series` translators:
#   . "$(cd "$(dirname "$0")/../../rt-series/tools" && pwd)/parity_contract.sh"
#
# Provides:
#   parity_init <repo_name>
#   parity_row <abi> <host> <case> <engine> <status> <elapsed_ms> [detail]
#   parity_norm_stderr <infile> <outfile>
#   parity_check_golden <golden_file> <actual_file>
#   parity_now_ms
#   parity_summary
#
# Status values:
#   PASS : Case executed and matched oracle/golden contract.
#   FAIL : Case executed and diverged or crashed.
#   GAP  : Required guest binary, golden, sysroot, or translator artifact missing.
#   SKIP : Skipped (causes non-zero exit unless PARITY_ALLOW_SKIP=1).
#
# Copyright 2026 Moritz Angermann <moritz@zw3rk.com>, zw3rk pte. ltd.
# SPDX-License-Identifier: Apache-2.0

PARITY_REPO=""
PARITY_PASS=0
PARITY_FAIL=0
PARITY_GAP=0
PARITY_SKIP=0
PARITY_ALLOW_SKIP="${PARITY_ALLOW_SKIP:-0}"
PARITY_UPDATE_GOLDEN="${PARITY_UPDATE_GOLDEN:-0}"
PARITY_TIER="${PARITY_TIER:-smoke}"

parity_init() {
    PARITY_REPO="${1:?parity_init requires repo name}"
    PARITY_PASS=0
    PARITY_FAIL=0
    PARITY_GAP=0
    PARITY_SKIP=0
    printf '== PARITY SUITE: %s (tier=%s) ==\n' "$PARITY_REPO" "$PARITY_TIER"
}

parity_now_ms() {
    if command -v python3 >/dev/null 2>&1; then
        python3 -c 'import time; print(int(time.time() * 1000))'
    else
        echo "0"
    fi
}

# parity_row <abi> <host> <case> <engine> <status> <elapsed_ms> [detail]
parity_row() {
    _pr_abi="${1:-default}"
    _pr_host="${2:-host}"
    _pr_case="${3:-case}"
    _pr_eng="${4:-engine}"
    _pr_st="${5:-FAIL}"
    _pr_ms="${6:-0}"
    _pr_det="${7:-}"

    case "$_pr_st" in
        PASS) PARITY_PASS=$((PARITY_PASS + 1)) ;;
        FAIL) PARITY_FAIL=$((PARITY_FAIL + 1)) ;;
        GAP)  PARITY_GAP=$((PARITY_GAP + 1)) ;;
        SKIP) PARITY_SKIP=$((PARITY_SKIP + 1)) ;;
        *)    PARITY_FAIL=$((PARITY_FAIL + 1)); _pr_st="FAIL" ;;
    esac

    printf 'PARITY_ROW\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
        "$PARITY_REPO" "$_pr_abi" "$_pr_host" "$_pr_case" "$_pr_eng" "$_pr_st" "$_pr_ms" "$_pr_det"
}

# Normalize host-specific harness lines (such as `hl: binder:` on hyper-linux)
parity_norm_stderr() {
    _pns_in="$1"
    _pns_out="$2"
    if [ -z "$_pns_in" ] || [ -z "$_pns_out" ] || [ ! -r "$_pns_in" ]; then
        return 2
    fi
    _pns_tmp="${_pns_out}.tmp.$$"
    _pns_rc=0
    grep -v -E '^(hl: |note: )' "$_pns_in" > "$_pns_tmp" 2>/dev/null || _pns_rc=$?
    if [ "$_pns_rc" -gt 1 ]; then
        rm -f "$_pns_tmp"
        return "$_pns_rc"
    fi
    mv "$_pns_tmp" "$_pns_out"
}

# Compare actual output file against committed golden file (or update if PARITY_UPDATE_GOLDEN=1)
parity_check_golden() {
    _pcg_golden="$1"
    _pcg_actual="$2"
    if [ -z "$_pcg_golden" ] || [ -z "$_pcg_actual" ] || [ ! -r "$_pcg_actual" ]; then
        return 2
    fi
    if [ "$PARITY_UPDATE_GOLDEN" = "1" ]; then
        _pcg_dir="$(dirname "$_pcg_golden")"
        if ! mkdir -p "$_pcg_dir"; then
            return 1
        fi
        _pcg_tmp="${_pcg_golden}.tmp.$$"
        if ! cp "$_pcg_actual" "$_pcg_tmp"; then
            rm -f "$_pcg_tmp"
            return 1
        fi
        if ! mv "$_pcg_tmp" "$_pcg_golden"; then
            rm -f "$_pcg_tmp"
            return 1
        fi
        return 0
    fi
    if [ ! -f "$_pcg_golden" ]; then
        return 2
    fi
    cmp -s "$_pcg_golden" "$_pcg_actual"
}

parity_summary() {
    printf 'PARITY_SUMMARY repo=%s pass=%d fail=%d gap=%d skip=%d\n' \
        "$PARITY_REPO" "$PARITY_PASS" "$PARITY_FAIL" "$PARITY_GAP" "$PARITY_SKIP"
    if [ "$PARITY_FAIL" -eq 0 ] && [ "$PARITY_GAP" -eq 0 ] && [ "$PARITY_PASS" -gt 0 ]; then
        if [ "$PARITY_SKIP" -eq 0 ] || [ "$PARITY_ALLOW_SKIP" = "1" ]; then
            printf '0 FAIL, 0 GAP (%s: %d PASS)\n' "$PARITY_REPO" "$PARITY_PASS"
            return 0
        fi
    fi
    printf 'PARITY GATE FAILED (%s: pass=%d fail=%d gap=%d skip=%d)\n' \
        "$PARITY_REPO" "$PARITY_PASS" "$PARITY_FAIL" "$PARITY_GAP" "$PARITY_SKIP" >&2
    return 1
}
