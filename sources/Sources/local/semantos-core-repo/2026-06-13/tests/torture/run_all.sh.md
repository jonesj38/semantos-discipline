---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/tests/torture/run_all.sh
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.589388+00:00
---

# tests/torture/run_all.sh

```sh
#!/usr/bin/env bash
# Torture test orchestrator — runs M1-T through M7-T + M3-T-Pask in dependency order.
#
# Usage:
#   bash tests/torture/run_all.sh [--duration-hours N] [--skip M2,M3Pask]
#
# Wave 1 (no deps): M1, M2, M3, M3Pask, M5  — run in parallel
# Wave 2 (deps on Wave 1): M4                — depends on M1
# Wave 3 (deps on Wave 2): M6               — depends on M1+M3+M5
# Wave 4 (deps on Wave 3): M7               — depends on M6
#
# M3Pask (M3-T-Pask) runs in Wave 1 alongside M3: it needs Pravega up (same
# as M3) and the combined pask-and-cell WASM (M1.12). Use --skip M3Pask to
# skip it when M1.12 is not yet built.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

DURATION_HOURS=24
SKIP=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --duration-hours) DURATION_HOURS="$2"; shift 2 ;;
        --skip)           SKIP="$2";           shift 2 ;;
        *) echo "Unknown arg: $1"; exit 1 ;;
    esac
done

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[0;33m'; NC='\033[0m'
pass() { echo -e "${GREEN}PASS${NC}  $*"; }
fail() { echo -e "${RED}FAIL${NC}  $*"; exit 1; }
skip() { echo -e "${YELLOW}SKIP${NC}  $*"; }
log()  { echo "[$(date -u +%H:%M:%S)] $*"; }

should_skip() { [[ ",${SKIP}," == *",$1,"* ]]; }

run_torture() {
    local name="$1"; local script="$2"
    if should_skip "${name}"; then
        skip "${name} (--skip)"
        return 0
    fi
    log "Starting ${name}…"
    DURATION_HOURS="${DURATION_HOURS}" bash "${script}" && pass "${name}" || fail "${name} FAILED"
}

log "Torture test run: M1–M7 + M3-T-Pask (${DURATION_HOURS}h duration)"
log "Skip: ${SKIP:-none}"

# ── Wave 1: no dependencies — run in parallel ─────────────────────────
log "=== Wave 1: M1, M2, M3, M3Pask, M5 (parallel) ==="

PIDS=()
NAMES=()

for pair in "M1:M1_torture.sh" "M2:M2_torture.sh" "M3:M3_torture.sh" "M3Pask:M3_Pask_torture.sh" "M5:M5_torture.sh"; do
    name="${pair%%:*}"; script="${pair##*:}"
    if should_skip "${name}"; then
        skip "${name} (--skip)"
    else
        DURATION_HOURS="${DURATION_HOURS}" bash "${SCRIPT_DIR}/${script}" \
            >> "${SCRIPT_DIR}/logs/${name}_orchestrator.log" 2>&1 &
        PIDS+=($!)
        NAMES+=("${name}")
    fi
done

WAVE1_OK=1
for i in "${!PIDS[@]}"; do
    pid="${PIDS[$i]}"; nm="${NAMES[$i]}"
    if wait "${pid}"; then
        pass "${nm}"
    else
        echo -e "${RED}FAIL${NC}  ${nm} — see ${SCRIPT_DIR}/logs/${nm}_orchestrator.log"
        WAVE1_OK=0
    fi
done
(( WAVE1_OK )) || fail "Wave 1 had failures; aborting"

# ── Wave 2: M4 depends on M1 ─────────────────────────────────────────
log "=== Wave 2: M4 (depends on M1) ==="
run_torture M4 "${SCRIPT_DIR}/M4_torture.sh"

# ── Wave 3: M6 depends on M1+M3+M5 ──────────────────────────────────
log "=== Wave 3: M6 (depends on M1+M3+M5) ==="
run_torture M6 "${SCRIPT_DIR}/M6_torture.sh"

# ── Wave 4: M7 depends on M6 ─────────────────────────────────────────
log "=== Wave 4: M7 (depends on M6) ==="
run_torture M7 "${SCRIPT_DIR}/M7_torture.sh"

pass "All torture tests PASSED (M1–M7 + M3-T-Pask, ${DURATION_HOURS}h)"

```
