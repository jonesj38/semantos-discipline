---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/tests/torture/M3_torture.sh
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.587694+00:00
---

# tests/torture/M3_torture.sh

```sh
#!/usr/bin/env bash
# M3-T — Pravega Streaming Torture Test.
#
# Per §6 M3-T conditions:
#   1. 20 Hz region-tick sustained for 24 h (1.7 M ticks total).
#   2. 100 simultaneous subscribers per stream.
#   3. Segment-rollover every 1 h.
#   4. Pravega-node kill + restart every 6 h; assert no event loss.
#   5. Subscriber kill + restart every 30 minutes; assert resume-from-last-acked.
#
# Pass criteria: zero event loss; no duplicate processing;
#   consumer lag < 1 s under steady state.
#
# Run: bash tests/torture/M3_torture.sh
# Requires: infra/pravega/docker-compose.yml up; Go test harness in infra/pravega/tests/

set -euo pipefail

: "${DURATION_HOURS:=24}"
: "${COMPOSE_FILE:=infra/pravega/docker-compose.yml}"
: "${TICK_HZ:=20}"
: "${SUBSCRIBER_COUNT:=100}"

DURATION_SECS=$(( DURATION_HOURS * 3600 ))
LOGDIR="$(dirname "$0")/logs"
mkdir -p "${LOGDIR}"
LOGFILE="${LOGDIR}/M3_torture_$(date +%Y%m%d_%H%M%S).log"
exec > >(tee -a "${LOGFILE}") 2>&1

RED='\033[0;31m'; GREEN='\033[0;32m'; NC='\033[0m'
pass() { echo -e "${GREEN}PASS${NC}  $*"; }
fail() { echo -e "${RED}FAIL${NC}  $*"; exit 1; }
log()  { echo "[$(date -u +%H:%M:%S)] $*"; }

log "M3-T torture test starting"
log "Duration: ${DURATION_HOURS}h, tick rate: ${TICK_HZ} Hz, subscribers: ${SUBSCRIBER_COUNT}"

# Validate prerequisites.
if ! command -v go &>/dev/null; then
    fail "go toolchain not found — M3 torture harness requires Go (or the gateway language chosen in M3.2)"
fi

if ! docker compose -f "${COMPOSE_FILE}" ps --services | grep -q pravega; then
    log "Starting Pravega cluster…"
    docker compose -f "${COMPOSE_FILE}" up -d
    sleep 30
fi

# ── build the Go torture harness ──────────────────────────────────────

HARNESS_DIR="infra/pravega/tests"
if [[ ! -f "${HARNESS_DIR}/go.mod" ]]; then
    fail "Go torture harness not found at ${HARNESS_DIR}/. Expected by M3.2 deliverable."
fi

(cd "${HARNESS_DIR}" && go build ./... >> "${LOGDIR}/harness_build.log" 2>&1) || \
    fail "Go harness build failed — see ${LOGDIR}/harness_build.log"

# ── condition 1+2: sustained ticks + 100 subscribers ─────────────────

log "=== Conditions 1+2: ${TICK_HZ} Hz producer + ${SUBSCRIBER_COUNT} subscribers ==="

(cd "${HARNESS_DIR}" && go run ./cmd/torture \
    --mode=produce-subscribe \
    --tick-hz="${TICK_HZ}" \
    --subscribers="${SUBSCRIBER_COUNT}" \
    --duration="${DURATION_SECS}" \
    >> "${LOGDIR}/m3_produce_subscribe.log" 2>&1) &
MAIN_PID=$!

# ── condition 3: segment rollover every 1 h ───────────────────────────

SEGMENT_INTERVAL=3600
NEXT_SEGMENT=$(( $(date +%s) + SEGMENT_INTERVAL ))

# ── condition 4: Pravega restart every 6 h ───────────────────────────

RESTART_INTERVAL=$(( 6 * 3600 ))
NEXT_RESTART=$(( $(date +%s) + RESTART_INTERVAL ))

# ── condition 5: subscriber restart every 30 minutes ─────────────────

SUB_RESTART_INTERVAL=1800
NEXT_SUB_RESTART=$(( $(date +%s) + SUB_RESTART_INTERVAL ))

END_TS=$(( $(date +%s) + DURATION_SECS ))

while (( $(date +%s) < END_TS )); do
    NOW=$(date +%s)

    if (( NOW >= NEXT_SEGMENT )); then
        log "Condition 3: triggering segment rollover"
        (cd "${HARNESS_DIR}" && go run ./cmd/torture --mode=rollover >> "${LOGDIR}/m3_rollover.log" 2>&1) || \
            fail "Segment rollover test failed"
        NEXT_SEGMENT=$(( NOW + SEGMENT_INTERVAL ))
    fi

    if (( NOW >= NEXT_RESTART )); then
        log "Condition 4: Pravega node restart"
        docker compose -f "${COMPOSE_FILE}" restart pravega
        sleep 20 # wait for reconnect
        (cd "${HARNESS_DIR}" && go run ./cmd/torture --mode=verify-no-loss >> "${LOGDIR}/m3_noloss.log" 2>&1) || \
            fail "Event-loss detected after Pravega restart"
        NEXT_RESTART=$(( NOW + RESTART_INTERVAL ))
        pass "Pravega restart: no event loss"
    fi

    if (( NOW >= NEXT_SUB_RESTART )); then
        log "Condition 5: subscriber restart"
        (cd "${HARNESS_DIR}" && go run ./cmd/torture --mode=subscriber-restart >> "${LOGDIR}/m3_subrestart.log" 2>&1) || \
            fail "Subscriber restart test failed (event loss or duplicate)"
        NEXT_SUB_RESTART=$(( NOW + SUB_RESTART_INTERVAL ))
        pass "Subscriber restart: resume-from-last-acked OK"
    fi

    if ! kill -0 "${MAIN_PID}" 2>/dev/null; then
        fail "Main produce-subscribe harness (PID ${MAIN_PID}) exited early"
    fi

    sleep 30
done

wait "${MAIN_PID}" || fail "Main produce-subscribe harness exited with error"

# ── final: verify exact-once delivery count ───────────────────────────

log "=== Final event count verification ==="
EXPECTED=$(( TICK_HZ * DURATION_SECS ))
(cd "${HARNESS_DIR}" && go run ./cmd/torture \
    --mode=count-events \
    --expected="${EXPECTED}" \
    >> "${LOGDIR}/m3_final_count.log" 2>&1) || fail "Final event count check failed"

pass "M3-T torture test PASSED (${DURATION_HOURS}h, ~${EXPECTED} events)"
log "Log: ${LOGFILE}"

```
