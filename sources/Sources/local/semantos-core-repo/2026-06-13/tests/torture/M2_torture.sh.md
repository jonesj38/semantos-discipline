---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/tests/torture/M2_torture.sh
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.587417+00:00
---

# tests/torture/M2_torture.sh

```sh
#!/usr/bin/env bash
# M2-T — SQLite Browser Tier Torture Test.
#
# Per §6 M2-T conditions:
#   1. Tab-kill mid-write every minute for an hour.
#   2. OPFS quota exhaustion (fill quota; assert graceful error).
#   3. 10 concurrent tabs writing to the same OPFS handle.
#   4. Browser refresh mid-cell-engine-execution; assert engine resumes.
#
# Pass criteria: no OPFS corruption; all valid writes durable;
#   concurrent-tab semantics enforce single-writer.
#
# Execution: Playwright + Chromium driving the world-client dev server.
# Run: bash tests/torture/M2_torture.sh [--base-url http://localhost:5175]

set -euo pipefail

: "${BASE_URL:=http://localhost:5175}"
: "${PLAYWRIGHT_BIN:=$(which playwright 2>/dev/null || echo "playwright-not-found")}"

LOGDIR="$(dirname "$0")/logs"
mkdir -p "${LOGDIR}"
LOGFILE="${LOGDIR}/M2_torture_$(date +%Y%m%d_%H%M%S).log"
exec > >(tee -a "${LOGFILE}") 2>&1

RED='\033[0;31m'; GREEN='\033[0;32m'; NC='\033[0m'
pass() { echo -e "${GREEN}PASS${NC}  $*"; }
fail() { echo -e "${RED}FAIL${NC}  $*"; exit 1; }
log()  { echo "[$(date -u +%H:%M:%S)] $*"; }

log "M2-T torture test starting"

if [[ "${PLAYWRIGHT_BIN}" == "playwright-not-found" ]]; then
    fail "playwright CLI not found. Install: pnpm add -D @playwright/test && playwright install chromium"
fi

# The actual M2-T scenario runs as a Playwright test suite.
# The suite is at apps/world-client/tests/torture/m2-torture.spec.ts.
# Here we invoke it; the spec file owns the detailed assertions.

log "=== Condition 1: Tab-kill mid-write (60 iterations over 1 h) ==="
"${PLAYWRIGHT_BIN}" test \
    --config apps/world-client/playwright.config.ts \
    --grep "M2-T.*tab-kill" \
    >> "${LOGDIR}/m2_tabkill.log" 2>&1 || fail "Tab-kill test failed — see ${LOGDIR}/m2_tabkill.log"
pass "Tab-kill test (condition 1)"

log "=== Condition 2: OPFS quota exhaustion ==="
"${PLAYWRIGHT_BIN}" test \
    --config apps/world-client/playwright.config.ts \
    --grep "M2-T.*quota" \
    >> "${LOGDIR}/m2_quota.log" 2>&1 || fail "Quota exhaustion test failed"
pass "OPFS quota exhaustion (condition 2)"

log "=== Condition 3: 10 concurrent tabs ==="
"${PLAYWRIGHT_BIN}" test \
    --config apps/world-client/playwright.config.ts \
    --grep "M2-T.*concurrent" \
    --workers=10 \
    >> "${LOGDIR}/m2_concurrent.log" 2>&1 || fail "Concurrent tabs test failed"
pass "10 concurrent tabs (condition 3)"

log "=== Condition 4: Browser refresh mid-execution ==="
"${PLAYWRIGHT_BIN}" test \
    --config apps/world-client/playwright.config.ts \
    --grep "M2-T.*refresh" \
    >> "${LOGDIR}/m2_refresh.log" 2>&1 || fail "Refresh-resume test failed"
pass "Refresh mid-execution (condition 4)"

pass "M2-T torture test PASSED"
log "Log: ${LOGFILE}"

```
