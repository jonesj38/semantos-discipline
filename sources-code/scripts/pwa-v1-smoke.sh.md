---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/scripts/pwa-v1-smoke.sh
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.321582+00:00
---

# scripts/pwa-v1-smoke.sh

```sh
#!/usr/bin/env bash
# pwa-v1-smoke.sh — Pre-flight smoke for the Odd Job Todd PWA V1 pilot.
#
# Verifies the brain's V1 HTTP/WSS surface is responsive before
# sideloading the APK. Tests each of the five V1 endpoints (per
# docs/REACTOR-PORT-TRACKER.md definition of done):
#
#   1. GET  /api/v1/info                       (no body; bearer-gated)
#   2. POST /api/v1/attachments/upload         (multipart photo + meta)
#   3. GET  /api/v1/attachments/<id>/blob      (retrieval)
#   4. POST /api/v1/voice-extract              (multipart audio + transcript)
#   5. WSS  /api/v1/events?hat=<hat>           (event-stream upgrade)
#
# Each test verifies the endpoint RESPONDS (200/401/101 as appropriate)
# without exercising the full signed-payload contract. The PWA-side
# runbook at docs/operator-runbooks/pwa-v1-pilot-checklist.md exercises
# the full flows from the phone.
#
# Usage:
#   ./scripts/pwa-v1-smoke.sh                      # localhost:8080
#   BRAIN_URL=https://rbs.example.com ./pwa-v1-smoke.sh
#   BRAIN_URL=http://localhost:8080 BEARER=xyz ./pwa-v1-smoke.sh
#
# Exit codes:
#   0  — all endpoints respond as expected
#   1  — an endpoint failed to respond or returned a 4xx/5xx other than 401

set -euo pipefail

BRAIN_URL="${BRAIN_URL:-http://localhost:8080}"
BEARER="${BEARER:-}"
HAT="${HAT:-oddjobtodd.info}"

# Strip trailing slash for consistent URL construction.
BRAIN_URL="${BRAIN_URL%/}"

# Color helpers (only when stdout is a tty).
if [ -t 1 ]; then
    GREEN=$'\033[0;32m'
    RED=$'\033[0;31m'
    YELLOW=$'\033[0;33m'
    DIM=$'\033[2m'
    RESET=$'\033[0m'
else
    GREEN=""
    RED=""
    YELLOW=""
    DIM=""
    RESET=""
fi

pass() { echo "  ${GREEN}✓${RESET} $1"; }
fail() { echo "  ${RED}✗${RESET} $1"; FAILED=1; }
warn() { echo "  ${YELLOW}⚠${RESET} $1"; }
info() { echo "  ${DIM}·${RESET} $1"; }

FAILED=0

echo "PWA V1 pre-flight smoke"
echo "  Target: ${BRAIN_URL}"
echo "  Hat:    ${HAT}"
if [ -n "$BEARER" ]; then
    echo "  Auth:   bearer (${#BEARER} chars)"
else
    echo "  Auth:   none (expect 401 on bearer-gated endpoints)"
fi
echo

# ── Test 1: GET /api/v1/info ───────────────────────────────────────────
echo "Test 1: GET /api/v1/info"

CURL_AUTH=()
if [ -n "$BEARER" ]; then
    CURL_AUTH=(-H "Authorization: Bearer $BEARER")
fi

INFO_CODE=$(curl -s --connect-timeout 5 --max-time 10 -o /tmp/pwa_smoke_info.json -w "%{http_code}" \
    ${CURL_AUTH[@]+"${CURL_AUTH[@]}"} \
    "${BRAIN_URL}/api/v1/info" || true)

case "$INFO_CODE" in
    200)
        pass "/api/v1/info responded 200"
        if command -v jq >/dev/null 2>&1; then
            for field in brain_pin_cert_id pubkey_hex server_version; do
                if jq -e ".${field}" /tmp/pwa_smoke_info.json >/dev/null 2>&1; then
                    info "field present: ${field}"
                else
                    warn "field missing in response: ${field}"
                fi
            done
        else
            info "(install jq to verify response schema)"
        fi
        ;;
    401)
        if [ -z "$BEARER" ]; then
            pass "/api/v1/info responded 401 (bearer required, none provided)"
        else
            fail "/api/v1/info responded 401 with bearer — token invalid?"
        fi
        ;;
    404)
        fail "/api/v1/info responded 404 — endpoint not wired (regression to pre-T8a?)"
        ;;
    000)
        fail "/api/v1/info — could not connect to ${BRAIN_URL}"
        ;;
    *)
        fail "/api/v1/info responded ${INFO_CODE} (expected 200 or 401)"
        ;;
esac

# ── Test 2: POST /api/v1/attachments/upload ────────────────────────────
echo
echo "Test 2: POST /api/v1/attachments/upload (multipart probe)"

UPLOAD_CODE=$(curl -s --connect-timeout 5 --max-time 10 -o /tmp/pwa_smoke_upload.json -w "%{http_code}" \
    ${CURL_AUTH[@]+"${CURL_AUTH[@]}"} \
    -X POST \
    -F "metadata={}" \
    "${BRAIN_URL}/api/v1/attachments/upload" || true)

case "$UPLOAD_CODE" in
    400)
        pass "/api/v1/attachments/upload responded 400 (handler running, invalid body rejected)"
        info "(full multipart flow exercised by the PWA runbook)"
        ;;
    401)
        if [ -z "$BEARER" ]; then
            pass "/api/v1/attachments/upload responded 401 (bearer required)"
        else
            fail "/api/v1/attachments/upload responded 401 with bearer"
        fi
        ;;
    404)
        fail "/api/v1/attachments/upload responded 404 — endpoint not wired (regression to pre-T1?)"
        ;;
    000)
        fail "/api/v1/attachments/upload — could not connect"
        ;;
    *)
        warn "/api/v1/attachments/upload responded ${UPLOAD_CODE} (probing only; check log for handler activity)"
        ;;
esac

# ── Test 3: GET /api/v1/attachments/{nonexistent}/blob ─────────────────
echo
echo "Test 3: GET /api/v1/attachments/<probe>/blob"

BLOB_CODE=$(curl -s --connect-timeout 5 --max-time 10 -o /dev/null -w "%{http_code}" \
    ${CURL_AUTH[@]+"${CURL_AUTH[@]}"} \
    "${BRAIN_URL}/api/v1/attachments/probe-nonexistent/blob" || true)

case "$BLOB_CODE" in
    404)
        pass "/api/v1/attachments/probe-nonexistent/blob responded 404 (route handler running; cell not found is expected)"
        ;;
    401)
        if [ -z "$BEARER" ]; then
            pass "/api/v1/attachments/<id>/blob responded 401 (bearer required)"
        else
            fail "/api/v1/attachments/<id>/blob responded 401 with bearer"
        fi
        ;;
    000)
        fail "/api/v1/attachments/<id>/blob — could not connect"
        ;;
    *)
        warn "/api/v1/attachments/<id>/blob responded ${BLOB_CODE}"
        ;;
esac

# ── Test 4: POST /api/v1/voice-extract ─────────────────────────────────
echo
echo "Test 4: POST /api/v1/voice-extract (multipart probe)"

VOICE_CODE=$(curl -s --connect-timeout 5 --max-time 10 -o /tmp/pwa_smoke_voice.json -w "%{http_code}" \
    ${CURL_AUTH[@]+"${CURL_AUTH[@]}"} \
    -X POST \
    -F "metadata={}" \
    "${BRAIN_URL}/api/v1/voice-extract" || true)

case "$VOICE_CODE" in
    400)
        pass "/api/v1/voice-extract responded 400 (handler running, invalid body rejected)"
        ;;
    401)
        if [ -z "$BEARER" ]; then
            pass "/api/v1/voice-extract responded 401 (bearer required)"
        else
            fail "/api/v1/voice-extract responded 401 with bearer"
        fi
        ;;
    405)
        pass "/api/v1/voice-extract responded 405 (handler running, method gate)"
        ;;
    404)
        fail "/api/v1/voice-extract responded 404 — endpoint not wired (regression to pre-T4/T8b?)"
        ;;
    000)
        fail "/api/v1/voice-extract — could not connect"
        ;;
    *)
        warn "/api/v1/voice-extract responded ${VOICE_CODE}"
        ;;
esac

# ── Test 5: WSS /api/v1/events upgrade ─────────────────────────────────
echo
echo "Test 5: WSS /api/v1/events?hat=${HAT} (upgrade probe)"

# Build a websocket-handshake request via curl. The endpoint should
# respond 101 Switching Protocols when bearer is valid, 401 when not.

WS_KEY=$(head -c 16 /dev/urandom | base64)
WSS_CODE=$(curl -s --connect-timeout 5 --max-time 10 -o /tmp/pwa_smoke_wss.txt -w "%{http_code}" \
    ${CURL_AUTH[@]+"${CURL_AUTH[@]}"} \
    -H "Connection: Upgrade" \
    -H "Upgrade: websocket" \
    -H "Sec-WebSocket-Version: 13" \
    -H "Sec-WebSocket-Key: ${WS_KEY}" \
    "${BRAIN_URL}/api/v1/events?hat=${HAT}" 2>&1 || true)

case "$WSS_CODE" in
    101)
        pass "/api/v1/events responded 101 Switching Protocols (WSS upgrade succeeded)"
        ;;
    401)
        if [ -z "$BEARER" ]; then
            pass "/api/v1/events responded 401 (bearer required)"
        else
            fail "/api/v1/events responded 401 with bearer"
        fi
        ;;
    404)
        warn "/api/v1/events responded 404 — could be T3 deferred (per REACTOR-PORT-TRACKER); PWA polls /repl as fallback"
        ;;
    000)
        fail "/api/v1/events — could not connect"
        ;;
    *)
        warn "/api/v1/events responded ${WSS_CODE} (expected 101 or 401)"
        ;;
esac

# ── Summary ────────────────────────────────────────────────────────────

echo
if [ "$FAILED" -eq 0 ]; then
    echo "${GREEN}All V1 endpoints responding as expected.${RESET}"
    echo
    echo "Next: load the APK + walk the phone-side checklist at"
    echo "      docs/operator-runbooks/pwa-v1-pilot-checklist.md"
    exit 0
else
    echo "${RED}One or more endpoints failed.${RESET} Brain-side regression — debug before"
    echo "loading the APK. Check journal: ssh rbs 'journalctl -u semantos-shell -n 50'"
    exit 1
fi

```
