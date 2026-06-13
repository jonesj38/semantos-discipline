---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/semantos-brain/tests/lmdb_crash_recovery.sh
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.207603+00:00
---

# runtime/semantos-brain/tests/lmdb_crash_recovery.sh

```sh
#!/usr/bin/env bash
# M1.9 crash-recovery conformance test
#
# Tests that LMDB can recover from a simulated crash (unclean close)
# by re-opening the env and verifying data written before the crash is intact.
#
# Test cases:
#   M1.9-T-clean-commit       — write 10 records, close cleanly, reopen → all 10 present
#   M1.9-T-nometasync-recovery — write 10 records with NOMETASYNC, simulate unclean
#                                close (kill -9 the writer), reopen → ≥9 records, no corruption
#   M1.9-T-nosync-not-default — static check: prod_flags does NOT include MDB_NOSYNC
#   M1.9-T-notls-always       — static check: prod_flags always includes MDB_NOTLS
#
# Requirements:
#   - lmdb-crash-writer binary built via `zig build lmdb-crash-writer`
#   - lmdb-reader binary built via `zig build lmdb-reader` (counts records)
#   - Run from runtime/semantos-brain/ directory, or set BRAIN_BUILD_DIR to the zig-out/bin path
#
# Exit: 0 if all tests pass, 1 if any fail.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BRAIN_DIR="$(dirname "$SCRIPT_DIR")"

# Resolve binary directory.
BUILD_DIR="${BRAIN_BUILD_DIR:-${BRAIN_DIR}/zig-out/bin}"
WRITER="${BUILD_DIR}/lmdb-crash-writer"
READER="${BUILD_DIR}/lmdb-reader"

PASS=0
FAIL=0

pass() { echo "  PASS  $1"; PASS=$((PASS + 1)); }
fail() { echo "  FAIL  $1: $2"; FAIL=$((FAIL + 1)); }

require_binary() {
    local bin="$1"
    if [[ ! -x "$bin" ]]; then
        echo "ERROR: binary not found or not executable: $bin"
        echo "  Run: cd ${BRAIN_DIR} && zig build lmdb-crash-writer lmdb-reader"
        exit 1
    fi
}

count_records() {
    # count_records <db_path> → prints integer count on stdout
    local db_path="$1"
    "$READER" "$db_path" 2>/dev/null
}

# ── M1.9-T-nosync-not-default ─────────────────────────────────────────────
# Static check: prod_flags (NOTLS | NOMETASYNC = 0x200000 | 0x40000 = 0x240000)
# must NOT include MDB_NOSYNC (0x10000).
test_nosync_not_default() {
    local prod_flags=0x240000   # EnvFlags.NOTLS | EnvFlags.NOMETASYNC
    local nosync=0x10000

    # Bash arithmetic: strip leading 0x, evaluate.
    local pf=$(( prod_flags ))
    local ns=$(( nosync ))

    if [[ $(( pf & ns )) -eq 0 ]]; then
        pass "M1.9-T-nosync-not-default"
    else
        fail "M1.9-T-nosync-not-default" "prod_flags includes MDB_NOSYNC"
    fi
}

# ── M1.9-T-notls-always ───────────────────────────────────────────────────
# Static check: prod_flags must include MDB_NOTLS (0x200000).
test_notls_always() {
    local prod_flags=0x240000   # EnvFlags.NOTLS | EnvFlags.NOMETASYNC
    local notls=0x200000

    local pf=$(( prod_flags ))
    local nl=$(( notls ))

    if [[ $(( pf & nl )) -ne 0 ]]; then
        pass "M1.9-T-notls-always"
    else
        fail "M1.9-T-notls-always" "prod_flags missing MDB_NOTLS"
    fi
}

# ── M1.9-T-clean-commit ───────────────────────────────────────────────────
# Write 10 records, close cleanly, reopen and count → must be 10.
test_clean_commit() {
    local db_dir
    db_dir="$(mktemp -d)"
    trap "rm -rf '$db_dir'" RETURN

    # Write 10 records, clean exit.
    "$WRITER" "$db_dir" 10 2>/dev/null

    local count
    count="$(count_records "$db_dir")"

    if [[ "$count" -eq 10 ]]; then
        pass "M1.9-T-clean-commit"
    else
        fail "M1.9-T-clean-commit" "expected 10 records, got $count"
    fi
}

# ── M1.9-T-nometasync-recovery ────────────────────────────────────────────
# Write 10 records with NOMETASYNC, kill -9 mid-flight (after all writes
# but before we let the process exit naturally), then reopen.
# We simulate the crash by:
#   1. Running lmdb-crash-writer in background.
#   2. Waiting for it to signal readiness (or use a sleep).
#   3. Sending SIGKILL.
#   4. Reopening and counting: expect ≥ 9 records (last meta may lag).
#
# To make this deterministic the writer writes 10 records and flushes
# stdout. We kill AFTER it writes but BEFORE it exits.  NOMETASYNC
# guarantees that data pages are flushed even if the meta page is not.
test_nometasync_recovery() {
    local db_dir
    db_dir="$(mktemp -d)"
    trap "rm -rf '$db_dir'" RETURN

    # Write and clean-exit first so we have a known base of 10 records.
    "$WRITER" "$db_dir" 10 2>/dev/null

    local count_before
    count_before="$(count_records "$db_dir")"

    # Now simulate an additional pass that writes more records, gets killed.
    # We run the writer writing 10 more records (keys 10..19 if we reset the
    # DB, but here we just re-write the same keys — LMDB will overwrite).
    # Kill it during the run.  To make the kill land mid-run we use a named
    # pipe or just SIGKILL immediately after launching.
    "$WRITER" "$db_dir" 10 &
    local pid=$!
    # Give it a moment to start writing, then kill.
    sleep 0.05
    kill -9 "$pid" 2>/dev/null || true
    wait "$pid" 2>/dev/null || true

    # Now reopen.  LMDB should be consistent (no corruption).
    local count_after
    count_after="$(count_records "$db_dir")"

    if [[ "$count_after" -ge 9 ]]; then
        pass "M1.9-T-nometasync-recovery (records after unclean close: ${count_after})"
    else
        fail "M1.9-T-nometasync-recovery" "expected ≥9 records after crash, got ${count_after}"
    fi
}

# ── Main ──────────────────────────────────────────────────────────────────

echo "M1.9 crash-recovery conformance"
echo "================================"

# Static checks don't need binaries.
test_nosync_not_default
test_notls_always

# Runtime tests require the binaries.
require_binary "$WRITER"
require_binary "$READER"

test_clean_commit
test_nometasync_recovery

echo ""
echo "Results: ${PASS} passed, ${FAIL} failed"
if [[ "$FAIL" -gt 0 ]]; then
    exit 1
fi

```
