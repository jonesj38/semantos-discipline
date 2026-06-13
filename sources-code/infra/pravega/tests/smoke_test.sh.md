---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/infra/pravega/tests/smoke_test.sh
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:19.043878+00:00
---

# infra/pravega/tests/smoke_test.sh

```sh
#!/usr/bin/env bash
# M3.1-T — Pravega single-node dev cluster smoke test.
#
# Acceptance: docker-compose brings up Pravega; one stream creates/writes/reads.
#
# Prerequisites:
#   - docker compose v2 (not docker-compose v1)
#   - curl, jq
#
# Usage:
#   cd <repo-root>
#   bash infra/pravega/tests/smoke_test.sh
#
# Exit codes:
#   0 — all assertions passed
#   1 — one or more assertions failed
#   2 — cluster did not become healthy within timeout

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
COMPOSE_FILE="${SCRIPT_DIR}/../docker-compose.yml"
CONTROLLER_URL="http://localhost:9090"
DATA_URL="http://localhost:9091"
TIMEOUT_SECS=120
SCOPE="semantos-test"
STREAM="smoke"

RED='\033[0;31m'; GREEN='\033[0;32m'; NC='\033[0m'
pass() { echo -e "${GREEN}PASS${NC} $*"; }
fail() { echo -e "${RED}FAIL${NC} $*"; exit 1; }

# ── bring up cluster ─────────────────────────────────────────────────

echo "==> Starting Pravega dev cluster…"
docker compose -f "${COMPOSE_FILE}" up -d

# ── wait for controller REST API ──────────────────────────────────────

echo "==> Waiting for controller (up to ${TIMEOUT_SECS}s)…"
deadline=$(( $(date +%s) + TIMEOUT_SECS ))
until curl -sf "${CONTROLLER_URL}/v1/ping" >/dev/null 2>&1; do
    if (( $(date +%s) > deadline )); then
        echo "Timed out waiting for Pravega controller"
        docker compose -f "${COMPOSE_FILE}" logs --tail=50
        exit 2
    fi
    sleep 3
done
pass "Controller REST API responding"

# ── M3.1-T-scope-create ───────────────────────────────────────────────

echo "==> Creating scope '${SCOPE}'…"
HTTP=$(curl -sf -o /dev/null -w "%{http_code}" -X POST \
    "${CONTROLLER_URL}/v1/scopes" \
    -H "Content-Type: application/json" \
    -d "{\"scopeName\":\"${SCOPE}\"}" || true)

if [[ "${HTTP}" != "201" && "${HTTP}" != "409" ]]; then
    fail "Scope create returned HTTP ${HTTP} (expected 201 or 409)"
fi
pass "Scope '${SCOPE}' created (HTTP ${HTTP})"

# ── M3.1-T-stream-create ──────────────────────────────────────────────

echo "==> Creating stream '${SCOPE}/${STREAM}'…"
HTTP=$(curl -sf -o /dev/null -w "%{http_code}" -X POST \
    "${CONTROLLER_URL}/v1/scopes/${SCOPE}/streams" \
    -H "Content-Type: application/json" \
    -d '{
        "streamName": "'"${STREAM}"'",
        "scalingPolicy": {"type":"FIXED_NUM_SEGMENTS","minNumSegments":1},
        "retentionPolicy": {"type":"UNLIMITED"}
    }' || true)

if [[ "${HTTP}" != "201" && "${HTTP}" != "409" ]]; then
    fail "Stream create returned HTTP ${HTTP} (expected 201 or 409)"
fi
pass "Stream '${SCOPE}/${STREAM}' created (HTTP ${HTTP})"

# ── M3.1-T-stream-event-write ─────────────────────────────────────────

echo "==> Writing one event to '${SCOPE}/${STREAM}'…"
EVENT_PAYLOAD='{"hello":"semantos","ts":"'"$(date -u +%Y-%m-%dT%H:%M:%SZ)"'"}'
HTTP=$(curl -sf -o /dev/null -w "%{http_code}" -X POST \
    "${DATA_URL}/v1/scopes/${SCOPE}/streams/${STREAM}/event" \
    -H "Content-Type: application/json" \
    -d "${EVENT_PAYLOAD}" || true)

# Pravega data plane returns 201 on successful append.
if [[ "${HTTP}" != "201" ]]; then
    fail "Event write returned HTTP ${HTTP} (expected 201)"
fi
pass "Event written to '${SCOPE}/${STREAM}'"

# ── M3.1-T-stream-event-read ──────────────────────────────────────────

echo "==> Reading from '${SCOPE}/${STREAM}'…"
READER_GROUP="smoke-rg-$(date +%s)"

# Create a reader group.
HTTP=$(curl -sf -o /dev/null -w "%{http_code}" -X POST \
    "${DATA_URL}/v1/scopes/${SCOPE}/readergroups" \
    -H "Content-Type: application/json" \
    -d '{
        "readerGroupName": "'"${READER_GROUP}"'",
        "streams": [{"scopeName":"'"${SCOPE}"'","streamName":"'"${STREAM}"'"}]
    }' || true)
if [[ "${HTTP}" != "201" ]]; then
    fail "Reader group create returned HTTP ${HTTP}"
fi

# Create a reader.
READER_ID="reader-1"
HTTP=$(curl -sf -o /dev/null -w "%{http_code}" -X POST \
    "${DATA_URL}/v1/scopes/${SCOPE}/readergroups/${READER_GROUP}/readers" \
    -H "Content-Type: application/json" \
    -d "{\"readerId\":\"${READER_ID}\"}" || true)
if [[ "${HTTP}" != "201" ]]; then
    fail "Reader create returned HTTP ${HTTP}"
fi

# Read one event.
RESPONSE=$(curl -sf \
    "${DATA_URL}/v1/scopes/${SCOPE}/readergroups/${READER_GROUP}/readers/${READER_ID}/events" \
    -H "Accept: application/json" || true)

if [[ -z "${RESPONSE}" ]]; then
    fail "Read returned empty response"
fi
pass "Event read from '${SCOPE}/${STREAM}': $(echo "${RESPONSE}" | head -c 80)"

echo ""
echo "M3.1 Pravega smoke tests PASSED"

```
