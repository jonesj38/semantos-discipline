---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/tests/torture/M7_torture.sh
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.588797+00:00
---

# tests/torture/M7_torture.sh

```sh
#!/usr/bin/env bash
# M7-T — Federation Torture Test.
#
# Per §6 M7-T conditions:
#   1. Network partition between two nodes for 30 minutes; cells routed
#      correctly to surviving partition.
#   2. One node simulated byzantine (returns wrong bytes); detection within 60 s,
#      eviction triggered.
#   3. New node joins; receives slot subset; reads work.
#   4. Old node leaves; slots rebalanced to remaining peers; reads continue.
#   5. Sustained 1000 fetches/sec across all 5 nodes for 24 h.
#
# Pass criteria: no incorrect bytes returned; no slot lost; no double-ownership;
#   rebalance completes < 5 minutes.

set -euo pipefail

: "${DURATION_HOURS:=24}"
: "${FETCH_RATE:=1000}"
: "${NODE_COUNT:=5}"
: "${PARTITION_MINUTES:=30}"
: "${BYZANTINE_DETECT_TIMEOUT:=60}"
: "${REBALANCE_TIMEOUT:=300}"
: "${FEDERATION_CONFIG:=infra/federation/cluster.yaml}"

DURATION_SECS=$(( DURATION_HOURS * 3600 ))
LOGDIR="$(dirname "$0")/logs"
mkdir -p "${LOGDIR}"
LOGFILE="${LOGDIR}/M7_torture_$(date +%Y%m%d_%H%M%S).log"
exec > >(tee -a "${LOGFILE}") 2>&1

RED='\033[0;31m'; GREEN='\033[0;32m'; NC='\033[0m'
pass() { echo -e "${GREEN}PASS${NC}  $*"; }
fail() { echo -e "${RED}FAIL${NC}  $*"; exit 1; }
log()  { echo "[$(date -u +%H:%M:%S)] $*"; }

log "M7-T federation torture test starting (${DURATION_HOURS}h)"
log "Nodes: ${NODE_COUNT}, fetch rate: ${FETCH_RATE}/s"

if ! command -v federation-cli &>/dev/null; then
    fail "federation-cli not found — required for M7 torture (built as part of M7 deliverables)"
fi

if ! command -v octave-torture &>/dev/null; then
    fail "octave-torture harness not found — required for fetch verification"
fi

# ── bootstrap 5-node federation ───────────────────────────────────────

log "Bootstrapping ${NODE_COUNT}-node federation…"
federation-cli cluster-start \
    --nodes="${NODE_COUNT}" \
    --config="${FEDERATION_CONFIG}" \
    >> "${LOGDIR}/m7_cluster.log" 2>&1 || fail "Federation cluster failed to start"

# Verify all nodes healthy and slots distributed.
federation-cli cluster-status \
    --config="${FEDERATION_CONFIG}" \
    --assert-balanced \
    >> "${LOGDIR}/m7_cluster.log" 2>&1 || fail "Federation cluster not balanced at startup"

log "Federation cluster up; slots distributed across ${NODE_COUNT} nodes"

# ── condition 5 (background): sustained 1000 fetches/sec ────────────

log "=== Condition 5 (background): ${FETCH_RATE} fetches/sec for ${DURATION_HOURS}h ==="

octave-torture fetch-sustained \
    --config="${FEDERATION_CONFIG}" \
    --rate="${FETCH_RATE}" \
    --duration="${DURATION_SECS}" \
    --verify-bytes \
    >> "${LOGDIR}/m7_sustained.log" 2>&1 &
FETCH_PID=$!
log "Sustained fetch worker PID: ${FETCH_PID}"

# ── condition 1: network partition for 30 minutes ────────────────────

log "=== Condition 1: partition nodes 4–5 from nodes 1–3 for ${PARTITION_MINUTES} min ==="

PARTITION_SECS=$(( PARTITION_MINUTES * 60 ))

federation-cli partition \
    --config="${FEDERATION_CONFIG}" \
    --partition-a="1,2,3" \
    --partition-b="4,5" \
    >> "${LOGDIR}/m7_partition.log" 2>&1 || fail "Could not inject network partition"

log "Partition active — verifying reads route to surviving partition…"
# Cells owned by nodes 4 and 5 should either be served from 1-3 replica or
# return a clean routing error (not wrong bytes).
octave-torture fetch-during-partition \
    --config="${FEDERATION_CONFIG}" \
    --partition-nodes="4,5" \
    --duration="${PARTITION_SECS}" \
    --verify-no-wrong-bytes \
    >> "${LOGDIR}/m7_partition.log" 2>&1 || fail "Wrong bytes served during partition"

federation-cli unpartition \
    --config="${FEDERATION_CONFIG}" \
    >> "${LOGDIR}/m7_partition.log" 2>&1 || fail "Could not heal network partition"

sleep 30 # allow reconnect and catch-up

federation-cli cluster-status \
    --config="${FEDERATION_CONFIG}" \
    --assert-balanced \
    >> "${LOGDIR}/m7_partition.log" 2>&1 || fail "Cluster not re-balanced after partition healed"

pass "Condition 1: partition routed correctly; no wrong bytes; cluster re-balanced"

# ── condition 2: byzantine node → detection + eviction ───────────────

log "=== Condition 2: byzantine node 3 (wrong bytes) — detect within ${BYZANTINE_DETECT_TIMEOUT}s ==="

federation-cli byzantine-start \
    --config="${FEDERATION_CONFIG}" \
    --node=3 \
    --mode=corrupt-bytes \
    >> "${LOGDIR}/m7_byzantine.log" 2>&1 || fail "Could not set node 3 to byzantine mode"

BYZANTINE_DETECTED=0
for (( elapsed=0; elapsed<=BYZANTINE_DETECT_TIMEOUT; elapsed+=5 )); do
    if federation-cli byzantine-check \
        --config="${FEDERATION_CONFIG}" \
        --node=3 \
        >> "${LOGDIR}/m7_byzantine.log" 2>&1; then
        BYZANTINE_DETECTED=1
        log "Byzantine node detected after ${elapsed}s"
        break
    fi
    sleep 5
done

(( BYZANTINE_DETECTED == 1 )) || fail "Byzantine node NOT detected within ${BYZANTINE_DETECT_TIMEOUT}s"

# Verify node 3 was evicted (no longer routing traffic).
federation-cli cluster-status \
    --config="${FEDERATION_CONFIG}" \
    --assert-node-evicted=3 \
    >> "${LOGDIR}/m7_byzantine.log" 2>&1 || fail "Byzantine node 3 not evicted after detection"

# Restore node 3 to healthy state.
federation-cli byzantine-stop \
    --config="${FEDERATION_CONFIG}" \
    --node=3 \
    >> "${LOGDIR}/m7_byzantine.log" 2>&1 || true
federation-cli node-rejoin \
    --config="${FEDERATION_CONFIG}" \
    --node=3 \
    >> "${LOGDIR}/m7_byzantine.log" 2>&1 || true

pass "Condition 2: byzantine node detected in ${elapsed}s (< ${BYZANTINE_DETECT_TIMEOUT}s), evicted"

# ── condition 3: new node joins → receives slots, reads work ─────────

log "=== Condition 3: new node 6 joins federation ==="

federation-cli node-add \
    --config="${FEDERATION_CONFIG}" \
    --node=6 \
    >> "${LOGDIR}/m7_join.log" 2>&1 || fail "Could not add node 6 to federation"

REBALANCE_START=$(date +%s)
# Wait for rebalance to complete.
REBALANCED=0
while (( $(date +%s) - REBALANCE_START < REBALANCE_TIMEOUT )); do
    if federation-cli cluster-status \
        --config="${FEDERATION_CONFIG}" \
        --assert-balanced \
        >> "${LOGDIR}/m7_join.log" 2>&1; then
        REBALANCED=1
        break
    fi
    sleep 10
done
REBALANCE_ELAPSED=$(( $(date +%s) - REBALANCE_START ))

(( REBALANCED == 1 )) || fail "Cluster not balanced ${REBALANCE_TIMEOUT}s after node 6 joined"
(( REBALANCE_ELAPSED < REBALANCE_TIMEOUT )) || \
    fail "Rebalance after join took ${REBALANCE_ELAPSED}s > ${REBALANCE_TIMEOUT}s"

# Verify reads still work (node 6 now holds ~16.7% of slots).
octave-torture fetch-spot-check \
    --config="${FEDERATION_CONFIG}" \
    --count=1000 \
    --verify-bytes \
    >> "${LOGDIR}/m7_join.log" 2>&1 || fail "Reads broken after node 6 joined"

pass "Condition 3: node 6 joined; rebalanced in ${REBALANCE_ELAPSED}s (< ${REBALANCE_TIMEOUT}s); reads work"

# ── condition 4: node leaves → slots rebalanced, reads continue ──────

log "=== Condition 4: node 2 leaves federation ==="

federation-cli node-remove \
    --config="${FEDERATION_CONFIG}" \
    --node=2 \
    >> "${LOGDIR}/m7_leave.log" 2>&1 || fail "Could not remove node 2 from federation"

REBALANCE_START=$(date +%s)
REBALANCED=0
while (( $(date +%s) - REBALANCE_START < REBALANCE_TIMEOUT )); do
    if federation-cli cluster-status \
        --config="${FEDERATION_CONFIG}" \
        --assert-balanced \
        --assert-no-double-ownership \
        >> "${LOGDIR}/m7_leave.log" 2>&1; then
        REBALANCED=1
        break
    fi
    sleep 10
done
REBALANCE_ELAPSED=$(( $(date +%s) - REBALANCE_START ))

(( REBALANCED == 1 )) || fail "Cluster not balanced ${REBALANCE_TIMEOUT}s after node 2 left"
(( REBALANCE_ELAPSED < REBALANCE_TIMEOUT )) || \
    fail "Rebalance after leave took ${REBALANCE_ELAPSED}s > ${REBALANCE_TIMEOUT}s"

# No slot should be lost: all previously written cells must still be readable.
octave-torture fetch-spot-check \
    --config="${FEDERATION_CONFIG}" \
    --count=1000 \
    --verify-bytes \
    >> "${LOGDIR}/m7_leave.log" 2>&1 || fail "Cells lost after node 2 departed"

pass "Condition 4: node 2 removed; rebalanced in ${REBALANCE_ELAPSED}s; no slot lost; reads continue"

# ── wait for sustained fetch to complete ─────────────────────────────

log "Waiting for sustained fetch worker to complete (${DURATION_HOURS}h)…"
wait "${FETCH_PID}" || fail "Sustained fetch worker (PID ${FETCH_PID}) exited with error — see ${LOGDIR}/m7_sustained.log"

# Final slot integrity check: no double-ownership, all slots covered.
federation-cli cluster-status \
    --config="${FEDERATION_CONFIG}" \
    --assert-balanced \
    --assert-no-double-ownership \
    --assert-no-lost-slots \
    >> "${LOGDIR}/m7_final.log" 2>&1 || fail "Final cluster integrity check failed"

pass "Condition 5: ${FETCH_RATE} fetches/sec sustained for ${DURATION_HOURS}h with no incorrect bytes"

federation-cli cluster-stop \
    --config="${FEDERATION_CONFIG}" \
    >> "${LOGDIR}/m7_cluster.log" 2>&1 || true

pass "M7-T torture test PASSED"
log "Log: ${LOGFILE}"

```
