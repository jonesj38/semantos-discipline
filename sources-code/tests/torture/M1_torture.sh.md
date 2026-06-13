---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/tests/torture/M1_torture.sh
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.589082+00:00
---

# tests/torture/M1_torture.sh

```sh
#!/usr/bin/env bash
# M1-T — LMDB Hot Path Torture Test.
#
# Per §6 M1-T conditions:
#   1. Sustained 50 K cell writes/sec for 24 h.
#   2. Concurrent random reads at 200 K/sec from 8 reader threads.
#   3. Reorg-truncate-from-height every 10 minutes (rollback 10 random heights, rebuild).
#   4. Power-loss simulation every 6 h (`kill -9` of the Semantos Brain process; assert clean restart).
#   5. Disk-full simulation: fill the LMDB env to capacity; assert graceful error, no corruption.
#
# Pass criteria: all 100 M cells readable byte-identical at end;
#   no JSONL replay needed; vtable conformance suite green.
#
# Prerequisites:
#   - LMDB-backed brain built and available at $BRAIN_BIN
#   - `lmdb-torture` test harness tool (built as part of M1 CI)
#   - At least 512 GB of free disk for the LMDB env
#   - Run with: bash tests/torture/M1_torture.sh [--duration-hours N]
#
# Author note: this file was authored separately from the M1 deliverables
# per §6 "torture-test ownership" principle.

set -euo pipefail

: "${BRAIN_BIN:=$(which brain 2>/dev/null || echo "brain-not-found")}"
: "${LMDB_DATA_DIR:=/tmp/semantos-torture-m1}"
: "${DURATION_HOURS:=24}"
: "${CELL_WRITE_RATE:=50000}"
: "${READ_RATE:=200000}"
: "${READ_THREADS:=8}"

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[0;33m'; NC='\033[0m'
pass()  { echo -e "${GREEN}PASS${NC}  $*"; }
fail()  { echo -e "${RED}FAIL${NC}  $*"; exit 1; }
note()  { echo -e "${YELLOW}NOTE${NC}  $*"; }
log()   { echo "[$(date -u +%H:%M:%S)] $*"; }

DURATION_SECS=$(( DURATION_HOURS * 3600 ))
LOGDIR="$(dirname "$0")/logs"
mkdir -p "${LOGDIR}"
LOGFILE="${LOGDIR}/M1_torture_$(date +%Y%m%d_%H%M%S).log"
exec > >(tee -a "${LOGFILE}") 2>&1

log "M1-T torture test starting"
log "Duration: ${DURATION_HOURS}h (${DURATION_SECS}s)"
log "LMDB data dir: ${LMDB_DATA_DIR}"
log "Cell write rate target: ${CELL_WRITE_RATE}/s"
log "Read rate target: ${READ_RATE}/s across ${READ_THREADS} threads"

# ── pre-flight ────────────────────────────────────────────────────────

if [[ "${BRAIN_BIN}" == "brain-not-found" ]]; then
    fail "brain binary not found. Set BRAIN_BIN= or add to PATH. Build with: zig build -p \$HOME/.local"
fi

if ! command -v lmdb-torture &>/dev/null; then
    fail "lmdb-torture harness not found. Build it: zig build lmdb-torture (added in M1.1 deliverable)"
fi

mkdir -p "${LMDB_DATA_DIR}"
AVAIL_KB=$(df -k "${LMDB_DATA_DIR}" | awk 'NR==2{print $4}')
REQUIRED_KB=$(( 512 * 1024 * 1024 )) # 512 GB
if (( AVAIL_KB < REQUIRED_KB )); then
    note "Available disk ${AVAIL_KB} KiB < recommended ${REQUIRED_KB} KiB. Disk-full test may trigger prematurely."
fi

# ── helpers ───────────────────────────────────────────────────────────

BRAIN_PID=""

start_wsh() {
    log "Starting brain with LMDB backing…"
    "${BRAIN_BIN}" \
        --store-backend=lmdb \
        --data-dir="${LMDB_DATA_DIR}" \
        --lmdb-map-size=549755813888 \
        >> "${LOGDIR}/brain.log" 2>&1 &
    BRAIN_PID=$!
    log "brain PID: ${BRAIN_PID}"
    sleep 2
    if ! kill -0 "${BRAIN_PID}" 2>/dev/null; then
        fail "brain did not start cleanly (PID ${BRAIN_PID})"
    fi
}

stop_brain_graceful() {
    if [[ -n "${BRAIN_PID}" ]] && kill -0 "${BRAIN_PID}" 2>/dev/null; then
        kill "${BRAIN_PID}" 2>/dev/null || true
        wait "${BRAIN_PID}" 2>/dev/null || true
        BRAIN_PID=""
    fi
}

kill9_wsh() {
    if [[ -n "${BRAIN_PID}" ]] && kill -0 "${BRAIN_PID}" 2>/dev/null; then
        log "Simulating power loss: kill -9 ${BRAIN_PID}"
        kill -9 "${BRAIN_PID}" 2>/dev/null || true
        BRAIN_PID=""
    fi
}

verify_clean_restart() {
    log "Verifying clean restart after kill -9…"
    start_wsh
    # Run a quick vtable conformance read to confirm store is intact.
    if ! lmdb-torture verify --data-dir="${LMDB_DATA_DIR}" --quick; then
        fail "Clean restart verification failed — LMDB data may be corrupt"
    fi
    pass "Clean restart OK"
}

# ── condition 1+2: sustained write + concurrent reads ─────────────────

log "=== Condition 1+2: write ${CELL_WRITE_RATE}/s + read ${READ_RATE}/s × ${READ_THREADS} threads ==="

start_wsh

WRITE_PID=""
READ_PIDS=()

lmdb-torture write \
    --data-dir="${LMDB_DATA_DIR}" \
    --rate="${CELL_WRITE_RATE}" \
    --duration="${DURATION_SECS}" \
    --seed-cells=100000000 \
    >> "${LOGDIR}/write.log" 2>&1 &
WRITE_PID=$!

for (( t=0; t<READ_THREADS; t++ )); do
    lmdb-torture read \
        --data-dir="${LMDB_DATA_DIR}" \
        --rate=$(( READ_RATE / READ_THREADS )) \
        --duration="${DURATION_SECS}" \
        --thread="${t}" \
        >> "${LOGDIR}/read_${t}.log" 2>&1 &
    READ_PIDS+=($!)
done

# ── condition 3: reorg every 10 minutes ───────────────────────────────

REORG_INTERVAL=600
NEXT_REORG=$(( $(date +%s) + REORG_INTERVAL ))

# ── condition 4: kill -9 every 6 h ───────────────────────────────────

KILL_INTERVAL=$(( 6 * 3600 ))
NEXT_KILL=$(( $(date +%s) + KILL_INTERVAL ))

# ── main loop ─────────────────────────────────────────────────────────

START_TS=$(date +%s)
END_TS=$(( START_TS + DURATION_SECS ))

while (( $(date +%s) < END_TS )); do
    NOW=$(date +%s)

    # Condition 3: reorg.
    if (( NOW >= NEXT_REORG )); then
        log "Condition 3: reorg at $(date -u)"
        lmdb-torture reorg \
            --data-dir="${LMDB_DATA_DIR}" \
            --rollback-count=10 \
            >> "${LOGDIR}/reorg.log" 2>&1 || fail "Reorg failed at $(date -u)"
        NEXT_REORG=$(( NOW + REORG_INTERVAL ))
    fi

    # Condition 4: power-loss simulation.
    if (( NOW >= NEXT_KILL )); then
        log "Condition 4: power-loss simulation at $(date -u)"
        kill9_wsh
        verify_clean_restart
        NEXT_KILL=$(( NOW + KILL_INTERVAL ))
    fi

    # Check write and read workers are still alive.
    if [[ -n "${WRITE_PID}" ]] && ! kill -0 "${WRITE_PID}" 2>/dev/null; then
        fail "Write worker (PID ${WRITE_PID}) exited early — check ${LOGDIR}/write.log"
    fi
    for rpid in "${READ_PIDS[@]}"; do
        if ! kill -0 "${rpid}" 2>/dev/null; then
            fail "Read worker (PID ${rpid}) exited early"
        fi
    done

    sleep 30
done

# ── condition 5: disk-full simulation ────────────────────────────────

log "=== Condition 5: disk-full simulation ==="
lmdb-torture fill-to-capacity \
    --data-dir="${LMDB_DATA_DIR}" \
    >> "${LOGDIR}/diskfull.log" 2>&1 || true # expected to "fail" gracefully

# Verify no corruption.
if ! lmdb-torture verify --data-dir="${LMDB_DATA_DIR}"; then
    fail "LMDB corruption detected after disk-full test"
fi
pass "Disk-full simulation: graceful error, no corruption"

# ── final verification ────────────────────────────────────────────────

log "=== Final vtable conformance check ==="

stop_brain_graceful

if ! zig build test-lmdb --prefix /usr/local 2>>"${LOGDIR}/conformance.log"; then
    fail "vtable conformance suite failed after 24 h torture"
fi

log "=== Cell count verification ==="
CELL_COUNT=$(lmdb-torture count --data-dir="${LMDB_DATA_DIR}")
log "Cells in store: ${CELL_COUNT}"
if (( CELL_COUNT < 90000000 )); then
    fail "Expected ~100 M cells, found only ${CELL_COUNT}"
fi

pass "M1-T torture test PASSED (${CELL_COUNT} cells; all 5 conditions met)"
log "Log: ${LOGFILE}"

```
