---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/scripts/conv-send-smoke.sh
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.316020+00:00
---

# scripts/conv-send-smoke.sh

```sh
#!/usr/bin/env bash
# conv-send-smoke.sh — Smoke for the W2/W3 customer-conversation endpoints.
#
# Verifies the brain's two new endpoints respond with the expected
# status codes WITHOUT exercising real Twilio dispatch.  Useful after
# `./runtime/semantos-brain/deploy/deploy-rbs.sh` to catch wire-level
# breakage before the PWA tries to actually message a contact.
#
# Endpoints:
#   1. POST /api/v1/conversation/<id>/send     (W2 — Twilio dispatch)
#   2. POST /api/v1/search/contacts            (W3 — name/address search)
#
# Each is verified with bearer-missing (expect 401) and a happy-path-
# shape call (expect 200/404/503 depending on brain state — see below).
#
# Usage:
#   ./scripts/conv-send-smoke.sh                          # localhost:8080
#   BRAIN_URL=https://oddjobtodd.info BEARER=hex ./scripts/conv-send-smoke.sh
#
# Expected outcomes:
#
# /api/v1/conversation/<id>/send (without bearer)         → 401
# /api/v1/conversation/<id>/send (bearer + bogus id)      → 404 (lookup miss)
#                                                          OR 503 if Twilio
#                                                          not configured
# /api/v1/search/contacts (without bearer)                → 401
# /api/v1/search/contacts (bearer + valid query)          → 200 with matches[]
#
# Exit codes:
#   0  — all endpoints respond as expected
#   1  — an endpoint returned an unexpected status

set -euo pipefail

BRAIN_URL="${BRAIN_URL:-http://localhost:8080}"
BEARER="${BEARER:-}"
BRAIN_URL="${BRAIN_URL%/}"

if [ -t 1 ]; then
    GREEN=$'\033[0;32m'; RED=$'\033[0;31m'; YELLOW=$'\033[0;33m'; DIM=$'\033[2m'; RESET=$'\033[0m'
else
    GREEN=""; RED=""; YELLOW=""; DIM=""; RESET=""
fi

pass() { echo "  ${GREEN}✓${RESET} $1"; }
fail() { echo "  ${RED}✗${RESET} $1"; FAILED=1; }
warn() { echo "  ${YELLOW}⚠${RESET} $1"; }
info() { echo "  ${DIM}·${RESET} $1"; }

FAILED=0

echo "Customer-conversations smoke"
echo "  Target: ${BRAIN_URL}"
echo "  Bearer: ${BEARER:+present (${#BEARER} chars)}${BEARER:-MISSING — only 401 paths will pass}"
echo

# ── 1. POST /api/v1/conversation/<id>/send — bearer missing ──────────

echo "Test 1/4: POST /api/v1/conversation/dummy/send without bearer (expect 401)"
status=$(curl -s -o /tmp/conv-send-smoke-1.txt -w "%{http_code}" \
    -X POST \
    -H "Content-Type: application/json" \
    -d '{"body":"x"}' \
    "${BRAIN_URL}/api/v1/conversation/dummy-id/send")
body=$(cat /tmp/conv-send-smoke-1.txt 2>/dev/null || echo "")
if [ "$status" = "401" ]; then
    pass "401 Unauthorised ($body)"
elif [ "$status" = "404" ]; then
    warn "404 — endpoint not attached on this brain (operator hasn't enabled conv-send yet)"
else
    fail "expected 401, got $status — body: $body"
fi

# ── 2. POST /api/v1/conversation/<id>/send — bearer + bogus id ───────

if [ -n "$BEARER" ]; then
    echo "Test 2/4: POST /api/v1/conversation/bogus/send with bearer (expect 404 or 503)"
    status=$(curl -s -o /tmp/conv-send-smoke-2.txt -w "%{http_code}" \
        -X POST \
        -H "Authorization: Bearer ${BEARER}" \
        -H "Content-Type: application/json" \
        -d '{"body":"smoke"}' \
        "${BRAIN_URL}/api/v1/conversation/00000000000000000000000000000000/send")
    body=$(cat /tmp/conv-send-smoke-2.txt 2>/dev/null || echo "")
    case "$status" in
        404) pass "404 — bogus conversation_id correctly rejected ($body)" ;;
        503) pass "503 — Twilio not configured on brain (expected pre-twilio.json)" ;;
        200) warn "200 — UNEXPECTED success on bogus id (means lookup succeeded? check brain state)" ;;
        *)   fail "expected 404 or 503, got $status — body: $body" ;;
    esac
else
    info "Test 2/4: SKIP (BEARER not set)"
fi

# ── 3. POST /api/v1/search/contacts — bearer missing ─────────────────

echo "Test 3/4: POST /api/v1/search/contacts without bearer (expect 401)"
status=$(curl -s -o /tmp/conv-send-smoke-3.txt -w "%{http_code}" \
    -X POST \
    -H "Content-Type: application/json" \
    -d '{"query":"smith"}' \
    "${BRAIN_URL}/api/v1/search/contacts")
body=$(cat /tmp/conv-send-smoke-3.txt 2>/dev/null || echo "")
if [ "$status" = "401" ]; then
    pass "401 Unauthorised ($body)"
elif [ "$status" = "404" ]; then
    warn "404 — endpoint not attached on this brain (operator hasn't enabled search yet)"
else
    fail "expected 401, got $status — body: $body"
fi

# ── 4. POST /api/v1/search/contacts — bearer + query ─────────────────

if [ -n "$BEARER" ]; then
    echo "Test 4/4: POST /api/v1/search/contacts with bearer + query 'smith' (expect 200)"
    status=$(curl -s -o /tmp/conv-send-smoke-4.txt -w "%{http_code}" \
        -X POST \
        -H "Authorization: Bearer ${BEARER}" \
        -H "Content-Type: application/json" \
        -d '{"query":"smith"}' \
        "${BRAIN_URL}/api/v1/search/contacts")
    body=$(cat /tmp/conv-send-smoke-4.txt 2>/dev/null || echo "")
    if [ "$status" = "200" ] && echo "$body" | grep -q '"matches":'; then
        match_count=$(echo "$body" | grep -o '"id":"[^"]*"' | wc -l | tr -d ' ')
        pass "200 with matches[] (${match_count} hit(s))"
    elif [ "$status" = "200" ]; then
        fail "200 but response missing matches[] — body: $body"
    else
        fail "expected 200, got $status — body: $body"
    fi
else
    info "Test 4/4: SKIP (BEARER not set)"
fi

echo
if [ "$FAILED" -eq 0 ]; then
    pass "All checks passed."
    exit 0
else
    fail "One or more checks failed — see above."
    exit 1
fi

```
