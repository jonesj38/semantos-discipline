---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/infra/pravega/tests/m3_2_gateway_test.sh
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:19.044170+00:00
---

# infra/pravega/tests/m3_2_gateway_test.sh

```sh
#!/usr/bin/env bash
# M3.2-T — Go gateway smoke test.
#
# Starts the gateway binary, writes one event through it, reads it back,
# asserts the response contains "M3.2".
#
# Prerequisites:
#   - infra/pravega-gateway binary already built:
#       cd infra/pravega-gateway && go build -o pravega-gateway .
#   - Pravega cluster running (M3.1 docker-compose up):
#       cd infra/pravega && docker compose up -d
#
# Skips gracefully if Pravega is not reachable.
#
# Usage:
#   bash infra/pravega/tests/m3_2_gateway_test.sh
#
# Exit codes:
#   0  — all assertions passed (or Pravega not available → skipped)
#   1  — one or more assertions failed

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"
GATEWAY_BIN="${REPO_ROOT}/infra/pravega-gateway/pravega-gateway"
CONTROLLER_URL="${PRAVEGA_CONTROLLER_URL:-http://localhost:9090}"
DATA_URL="${PRAVEGA_DATA_URL:-http://localhost:9091}"
GATEWAY_PORT="${PRAVEGA_GATEWAY_PORT:-7180}"
GATEWAY_URL="http://127.0.0.1:${GATEWAY_PORT}"
SCOPE="semantos-m32-test"
STREAM="m32-smoke"
TIMEOUT_SECS=30
GATEWAY_PID=""

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
pass()   { echo -e "${GREEN}PASS${NC} $*"; }
fail()   { echo -e "${RED}FAIL${NC} $*"; exit 1; }
skip()   { echo -e "${YELLOW}SKIP${NC} $*"; exit 0; }
info()   { echo "     $*"; }

cleanup() {
    if [[ -n "${GATEWAY_PID}" ]]; then
        kill "${GATEWAY_PID}" 2>/dev/null || true
        wait "${GATEWAY_PID}" 2>/dev/null || true
        info "Gateway (PID ${GATEWAY_PID}) stopped."
    fi
}
trap cleanup EXIT

# ── Check Pravega availability ────────────────────────────────────────────────

echo "==> Checking Pravega cluster at ${CONTROLLER_URL}…"
if ! curl -sf "${CONTROLLER_URL}/v1/ping" >/dev/null 2>&1; then
    skip "Pravega controller not reachable at ${CONTROLLER_URL} — run docker compose up -d first"
fi
info "Pravega cluster responding."

# ── Build gateway ─────────────────────────────────────────────────────────────

echo "==> Building gateway binary…"
if [[ ! -f "${GATEWAY_BIN}" ]]; then
    (cd "${REPO_ROOT}/infra/pravega-gateway" && go build -o pravega-gateway .) \
        || fail "go build failed"
fi
info "Binary: ${GATEWAY_BIN}"

# ── Start gateway ─────────────────────────────────────────────────────────────

echo "==> Starting gateway on port ${GATEWAY_PORT}…"
PRAVEGA_CONTROLLER_URL="${CONTROLLER_URL}" \
PRAVEGA_DATA_URL="${DATA_URL}" \
PRAVEGA_GATEWAY_PORT="${GATEWAY_PORT}" \
    "${GATEWAY_BIN}" >/tmp/pravega-gateway.log 2>&1 &
GATEWAY_PID=$!
info "Gateway PID: ${GATEWAY_PID}"

# Wait for /health to respond.
echo "==> Waiting for gateway /health (up to ${TIMEOUT_SECS}s)…"
deadline=$(( $(date +%s) + TIMEOUT_SECS ))
until curl -sf "${GATEWAY_URL}/health" >/dev/null 2>&1; do
    if (( $(date +%s) > deadline )); then
        echo "Gateway did not become healthy in time. Log:"
        cat /tmp/pravega-gateway.log || true
        fail "Gateway health timeout"
    fi
    sleep 0.5
done
pass "Gateway /health responding"

# ── M3.2-T-create-scope ───────────────────────────────────────────────────────

echo "==> Creating scope '${SCOPE}'…"
HTTP=$(curl -sf -o /dev/null -w "%{http_code}" -X POST \
    "${GATEWAY_URL}/v1/scopes" \
    -H "Content-Type: application/json" \
    -d "{\"scopeName\":\"${SCOPE}\"}" || true)
if [[ "${HTTP}" != "201" && "${HTTP}" != "409" ]]; then
    fail "Scope create returned HTTP ${HTTP} (expected 201 or 409)"
fi
pass "Scope '${SCOPE}' (HTTP ${HTTP})"

# ── M3.2-T-create-stream ──────────────────────────────────────────────────────

echo "==> Creating stream '${SCOPE}/${STREAM}'…"
HTTP=$(curl -sf -o /dev/null -w "%{http_code}" -X POST \
    "${GATEWAY_URL}/v1/scopes/${SCOPE}/streams" \
    -H "Content-Type: application/json" \
    -d "{\"streamName\":\"${STREAM}\",\"scalingPolicy\":{\"type\":\"FIXED_NUM_SEGMENTS\",\"minNumSegments\":1},\"retentionPolicy\":{\"type\":\"UNLIMITED\"}}" \
    || true)
if [[ "${HTTP}" != "201" && "${HTTP}" != "409" ]]; then
    fail "Stream create returned HTTP ${HTTP} (expected 201 or 409)"
fi
pass "Stream '${SCOPE}/${STREAM}' (HTTP ${HTTP})"

# ── M3.2-T-write-event ────────────────────────────────────────────────────────

echo "==> Writing event…"
EVENT='{"hello":"M3.2","from":"go-gateway"}'
HTTP=$(curl -sf -o /dev/null -w "%{http_code}" -X POST \
    "${GATEWAY_URL}/v1/scopes/${SCOPE}/streams/${STREAM}/events" \
    -H "Content-Type: application/json" \
    -d "${EVENT}" || true)
if [[ "${HTTP}" != "201" ]]; then
    fail "Event write returned HTTP ${HTTP} (expected 201)"
fi
pass "Event written (HTTP ${HTTP})"

# ── M3.2-T-create-reader-group ────────────────────────────────────────────────

RG="m32-smoke-rg-$(date +%s)"
echo "==> Creating reader group '${RG}'…"
HTTP=$(curl -sf -o /dev/null -w "%{http_code}" -X POST \
    "${GATEWAY_URL}/v1/scopes/${SCOPE}/readergroups" \
    -H "Content-Type: application/json" \
    -d "{\"readerGroupName\":\"${RG}\",\"streams\":[{\"scopeName\":\"${SCOPE}\",\"streamName\":\"${STREAM}\"}]}" \
    || true)
if [[ "${HTTP}" != "201" ]]; then
    fail "Reader group create returned HTTP ${HTTP} (expected 201)"
fi
pass "Reader group '${RG}' (HTTP ${HTTP})"

# ── M3.2-T-create-reader ──────────────────────────────────────────────────────

READER_ID="reader-1"
echo "==> Creating reader '${READER_ID}'…"
HTTP=$(curl -sf -o /dev/null -w "%{http_code}" -X POST \
    "${GATEWAY_URL}/v1/scopes/${SCOPE}/readergroups/${RG}/readers" \
    -H "Content-Type: application/json" \
    -d "{\"readerId\":\"${READER_ID}\"}" || true)
if [[ "${HTTP}" != "201" ]]; then
    fail "Reader create returned HTTP ${HTTP} (expected 201)"
fi
pass "Reader '${READER_ID}' (HTTP ${HTTP})"

# ── M3.2-T-read-event ─────────────────────────────────────────────────────────

echo "==> Reading event…"
RESPONSE=$(curl -sf \
    "${GATEWAY_URL}/v1/scopes/${SCOPE}/readergroups/${RG}/readers/${READER_ID}/events" \
    -H "Accept: application/json" || true)

if [[ -z "${RESPONSE}" ]]; then
    fail "Read returned empty response"
fi

if ! echo "${RESPONSE}" | grep -q "M3.2"; then
    fail "Response does not contain 'M3.2': ${RESPONSE}"
fi
pass "Event read contains 'M3.2': $(echo "${RESPONSE}" | head -c 120)"

# ── Summary ───────────────────────────────────────────────────────────────────

echo ""
echo "M3.2 gateway smoke tests PASSED"

```
