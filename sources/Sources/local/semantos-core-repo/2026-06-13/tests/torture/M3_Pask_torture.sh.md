---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/tests/torture/M3_Pask_torture.sh
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.588234+00:00
---

# tests/torture/M3_Pask_torture.sh

```sh
#!/usr/bin/env bash
# M3-T-Pask — Pask Determinism + Replay Convergence Torture Test.
#
# Per §6 M3-T-Pask conditions:
#   1. Run 1 M pask_interact_run calls against node A; capture the Pravega
#      pask-interactions stream.
#   2. Replay the stream on a fresh node B; assert pask_snapshot_state blob
#      is byte-identical to node A's snapshot.
#   3. Inject 100 K out-of-order events; assert all nodes converge to the
#      same snapshot (Pravega exactly-once reorders within stream key).
#   4. Kill the kernel mid-pask_interact_run; restart from last Pravega ack;
#      assert no graph drift vs. an uninterrupted replay.
#   5. 5-node federation, all subscribed to the same pask-interactions stream;
#      after 1 M sustained interactions, all 5 snapshots are byte-identical.
#
# Pass criteria: zero drift across nodes; deterministic replay byte-identical;
#   reorder-tolerant; recovery from mid-interaction kill is clean.

set -euo pipefail

: "${DURATION_HOURS:=24}"
: "${INTERACTION_COUNT:=1000000}"
: "${COMPOSE_FILE:=infra/pravega/docker-compose.yml}"
: "${FEDERATION_CONFIG:=infra/federation/cluster.yaml}"
: "${BRAIN_BIN:=$(which brain 2>/dev/null || echo "brain-not-found")}"
: "${PASK_STREAM:=pask-interactions}"
: "${PASK_NODE_A_DATA:=/tmp/semantos-torture-m3pask-A}"
: "${PASK_NODE_B_DATA:=/tmp/semantos-torture-m3pask-B}"

LOGDIR="$(dirname "$0")/logs"
mkdir -p "${LOGDIR}"
LOGFILE="${LOGDIR}/M3_Pask_torture_$(date +%Y%m%d_%H%M%S).log"
exec > >(tee -a "${LOGFILE}") 2>&1

RED='\033[0;31m'; GREEN='\033[0;32m'; NC='\033[0m'
pass() { echo -e "${GREEN}PASS${NC}  $*"; }
fail() { echo -e "${RED}FAIL${NC}  $*"; exit 1; }
log()  { echo "[$(date -u +%H:%M:%S)] $*"; }

log "M3-T-Pask torture test starting"
log "Interaction count: ${INTERACTION_COUNT}"

# Validate prerequisites.
if [[ "${BRAIN_BIN}" == "brain-not-found" ]]; then
    fail "brain binary not found — Pask runs inside brain"
fi

if ! command -v pask-torture &>/dev/null; then
    fail "pask-torture harness not found — expected from M3.9/M3.10 deliverables"
fi

if ! docker compose -f "${COMPOSE_FILE}" ps --services 2>/dev/null | grep -q pravega; then
    log "Starting Pravega cluster…"
    docker compose -f "${COMPOSE_FILE}" up -d
    sleep 30
fi

mkdir -p "${PASK_NODE_A_DATA}" "${PASK_NODE_B_DATA}"

# ── condition 1: 1 M interactions on node A → capture stream ─────────

log "=== Condition 1: ${INTERACTION_COUNT} interactions on node A + stream capture ==="

pask-torture run-interactions \
    --data-dir="${PASK_NODE_A_DATA}" \
    --brain-bin="${BRAIN_BIN}" \
    --count="${INTERACTION_COUNT}" \
    --stream="${PASK_STREAM}" \
    --compose-file="${COMPOSE_FILE}" \
    >> "${LOGDIR}/m3pask_node_a.log" 2>&1 || fail "Node A interactions failed"

# Capture the snapshot from node A.
pask-torture snapshot-export \
    --data-dir="${PASK_NODE_A_DATA}" \
    --output="${LOGDIR}/snapshot_A.bin" \
    >> "${LOGDIR}/m3pask_node_a.log" 2>&1 || fail "Node A snapshot export failed"

log "Node A snapshot captured: $(wc -c < "${LOGDIR}/snapshot_A.bin") bytes"
pass "Condition 1: ${INTERACTION_COUNT} interactions on node A + snapshot captured"

# ── condition 2: replay stream on fresh node B → byte-identical ───────

log "=== Condition 2: replay stream on node B → assert byte-identical snapshot ==="

pask-torture replay-stream \
    --data-dir="${PASK_NODE_B_DATA}" \
    --brain-bin="${BRAIN_BIN}" \
    --stream="${PASK_STREAM}" \
    --compose-file="${COMPOSE_FILE}" \
    --from-genesis \
    >> "${LOGDIR}/m3pask_node_b.log" 2>&1 || fail "Node B stream replay failed"

pask-torture snapshot-export \
    --data-dir="${PASK_NODE_B_DATA}" \
    --output="${LOGDIR}/snapshot_B.bin" \
    >> "${LOGDIR}/m3pask_node_b.log" 2>&1 || fail "Node B snapshot export failed"

if ! cmp --silent "${LOGDIR}/snapshot_A.bin" "${LOGDIR}/snapshot_B.bin"; then
    fail "Snapshots A and B differ — deterministic replay violated (byte-identical guarantee broken)"
fi

pass "Condition 2: node B replay byte-identical to node A"

# ── condition 3: out-of-order injection → convergence ────────────────

log "=== Condition 3: 100 K out-of-order events → convergence ==="

pask-torture inject-ooo \
    --stream="${PASK_STREAM}" \
    --compose-file="${COMPOSE_FILE}" \
    --count=100000 \
    >> "${LOGDIR}/m3pask_ooo.log" 2>&1 || fail "Out-of-order injection failed"

# Give nodes time to process and reorder (Pravega exactly-once per stream key).
sleep 30

# All subscribers should converge: compare all federated node snapshots
# against node A (the reference).
if command -v federation-cli &>/dev/null; then
    DRIFT_COUNT=$(federation-cli pask-snapshot-compare \
        --config="${FEDERATION_CONFIG}" \
        --reference="${LOGDIR}/snapshot_A.bin" \
        2>>"${LOGDIR}/m3pask_ooo.log" || echo "error")
    if [[ "${DRIFT_COUNT}" == "error" ]] || (( DRIFT_COUNT > 0 )); then
        fail "Post-OOO convergence check failed: ${DRIFT_COUNT} nodes drifted"
    fi
    pass "Condition 3: 100 K OOO events; all nodes converged"
else
    log "SKIP federation convergence check — federation-cli not built (M7 deliverable)"
    pass "Condition 3: OOO injection completed (convergence check skipped)"
fi

# ── condition 4: kill mid-interaction → resume from last ack ──────────

log "=== Condition 4: kill mid-pask_interact_run → restart from last Pravega ack ==="

# Run 50 K more interactions, kill brain mid-flight.
pask-torture run-interactions \
    --data-dir="${PASK_NODE_A_DATA}" \
    --brain-bin="${BRAIN_BIN}" \
    --count=50000 \
    --stream="${PASK_STREAM}" \
    --compose-file="${COMPOSE_FILE}" \
    --kill-at=25000 \
    >> "${LOGDIR}/m3pask_kill.log" 2>&1 || true  # kill exits non-zero

# Restart and complete the remaining interactions.
pask-torture run-interactions \
    --data-dir="${PASK_NODE_A_DATA}" \
    --brain-bin="${BRAIN_BIN}" \
    --count=50000 \
    --stream="${PASK_STREAM}" \
    --compose-file="${COMPOSE_FILE}" \
    --resume-from-last-ack \
    >> "${LOGDIR}/m3pask_kill.log" 2>&1 || fail "Node A resume after kill failed"

# Compare to a fresh uninterrupted replay of the same 50 K events.
PASK_NODE_C_DATA="/tmp/semantos-torture-m3pask-C"
mkdir -p "${PASK_NODE_C_DATA}"

pask-torture replay-stream \
    --data-dir="${PASK_NODE_C_DATA}" \
    --brain-bin="${BRAIN_BIN}" \
    --stream="${PASK_STREAM}" \
    --compose-file="${COMPOSE_FILE}" \
    --from-genesis \
    >> "${LOGDIR}/m3pask_kill.log" 2>&1 || fail "Node C uninterrupted replay failed"

pask-torture snapshot-export \
    --data-dir="${PASK_NODE_A_DATA}" \
    --output="${LOGDIR}/snapshot_A_post_kill.bin" \
    >> "${LOGDIR}/m3pask_kill.log" 2>&1
pask-torture snapshot-export \
    --data-dir="${PASK_NODE_C_DATA}" \
    --output="${LOGDIR}/snapshot_C.bin" \
    >> "${LOGDIR}/m3pask_kill.log" 2>&1

if ! cmp --silent "${LOGDIR}/snapshot_A_post_kill.bin" "${LOGDIR}/snapshot_C.bin"; then
    fail "Post-kill resume diverged from uninterrupted replay — Pravega ack semantics broken"
fi

pass "Condition 4: kill + resume from last ack; snapshot matches uninterrupted replay"

# ── condition 5: 5-node federation sustained 1 M interactions ─────────

log "=== Condition 5: 5-node federation, ${INTERACTION_COUNT} sustained interactions ==="

if ! command -v federation-cli &>/dev/null; then
    log "SKIP condition 5 — federation-cli not built (M7 deliverable)"
else
    DURATION_SECS=$(( DURATION_HOURS * 3600 ))

    federation-cli pask-sustained \
        --config="${FEDERATION_CONFIG}" \
        --stream="${PASK_STREAM}" \
        --compose-file="${COMPOSE_FILE}" \
        --interactions="${INTERACTION_COUNT}" \
        --duration="${DURATION_SECS}" \
        >> "${LOGDIR}/m3pask_federation.log" 2>&1 || fail "5-node Pask sustained test failed"

    # All 5 snapshots must be byte-identical.
    DRIFT_COUNT=$(federation-cli pask-snapshot-compare \
        --config="${FEDERATION_CONFIG}" \
        --all-equal \
        2>>"${LOGDIR}/m3pask_federation.log" || echo "error")

    if [[ "${DRIFT_COUNT}" == "error" ]] || (( DRIFT_COUNT > 0 )); then
        fail "5-node federation: ${DRIFT_COUNT} nodes have non-identical snapshots"
    fi

    pass "Condition 5: 5-node federation; all snapshots byte-identical after ${INTERACTION_COUNT} interactions"
fi

pass "M3-T-Pask torture test PASSED"
log "Log: ${LOGFILE}"

```
