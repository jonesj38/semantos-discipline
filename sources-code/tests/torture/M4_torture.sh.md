---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/tests/torture/M4_torture.sh
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.587962+00:00
---

# tests/torture/M4_torture.sh

```sh
#!/usr/bin/env bash
# M4-T — Octave Escalation Torture Test.
#
# Per §6 M4-T conditions:
#   1. 1 M random 1024-byte windowed reads against octave-1 cells over 24 h.
#   2. 100 K windowed reads against octave-2 cells (HTTP range).
#   3. MFP budget exhaustion mid-fetch every 1000 reads; assert clean rejection.
#   4. Pointer-cell forging attempt: feed a malformed pointer cell; assert K4 failure-atomic.
#   5. Nested-pointer auto-dereference attempt: chain pointer → pointer; assert no auto-deref.
#
# Pass criteria: no incorrect bytes returned; no kernel crash; MFP metering exact;
#   all forging attempts rejected.

set -euo pipefail

: "${BRAIN_BIN:=$(which brain 2>/dev/null || echo "brain-not-found")}"
: "${OCTAVE1_DATA_DIR:=/tmp/semantos-torture-m4-oct1}"
: "${DURATION_HOURS:=24}"

DURATION_SECS=$(( DURATION_HOURS * 3600 ))
LOGDIR="$(dirname "$0")/logs"
mkdir -p "${LOGDIR}"
LOGFILE="${LOGDIR}/M4_torture_$(date +%Y%m%d_%H%M%S).log"
exec > >(tee -a "${LOGFILE}") 2>&1

RED='\033[0;31m'; GREEN='\033[0;32m'; NC='\033[0m'
pass() { echo -e "${GREEN}PASS${NC}  $*"; }
fail() { echo -e "${RED}FAIL${NC}  $*"; exit 1; }
log()  { echo "[$(date -u +%H:%M:%S)] $*"; }

log "M4-T torture test starting (${DURATION_HOURS}h)"

if [[ "${BRAIN_BIN}" == "brain-not-found" ]]; then
    fail "brain binary not found"
fi

if ! command -v octave-torture &>/dev/null; then
    fail "octave-torture harness not found — built as part of M4 CI"
fi

# ── condition 1: 1 M windowed reads (octave 1) ───────────────────────

log "=== Condition 1: 1 M random octave-1 windowed reads ==="
octave-torture read-oct1 \
    --data-dir="${OCTAVE1_DATA_DIR}" \
    --count=1000000 \
    --verify-bytes \
    >> "${LOGDIR}/m4_oct1_reads.log" 2>&1 || fail "Octave-1 read test failed"
pass "Octave-1: 1 M reads, bytes verified"

# ── condition 2: 100 K windowed reads (octave 2 via HTTP) ────────────

log "=== Condition 2: 100 K octave-2 windowed reads (HTTP range) ==="
octave-torture read-oct2 \
    --count=100000 \
    --verify-bytes \
    >> "${LOGDIR}/m4_oct2_reads.log" 2>&1 || fail "Octave-2 HTTP range read test failed"
pass "Octave-2: 100 K HTTP-range reads, bytes verified"

# ── condition 3: MFP budget exhaustion ───────────────────────────────

log "=== Condition 3: MFP budget exhaustion every 1000 reads ==="
octave-torture mfp-budget \
    --count=1000000 \
    --exhaust-every=1000 \
    >> "${LOGDIR}/m4_mfp.log" 2>&1 || fail "MFP budget exhaustion test failed"
pass "MFP metering: budget exhaustion yields clean rejection"

# ── condition 4: pointer-cell forging ────────────────────────────────

log "=== Condition 4: malformed pointer cell (K4 failure-atomic) ==="
octave-torture forge-pointer \
    --attempts=10000 \
    >> "${LOGDIR}/m4_forge.log" 2>&1 || fail "Pointer forging test failed — kernel may have accepted malformed cell"
pass "Pointer forging: all 10 K malformed cells rejected (K4 intact)"

# ── condition 5: nested-pointer auto-deref prevention ────────────────

log "=== Condition 5: nested pointer → pointer, no auto-deref ==="
octave-torture nested-pointer \
    --chain-length=10 \
    --attempts=1000 \
    >> "${LOGDIR}/m4_nested.log" 2>&1 || fail "Nested pointer auto-deref test failed"
pass "Nested pointer: no auto-deref (each hop requires explicit OP_DEREF_POINTER)"

pass "M4-T torture test PASSED"
log "Log: ${LOGFILE}"

```
