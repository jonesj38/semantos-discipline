---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/scripts/smoke-test-mobile.sh
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.324987+00:00
---

# scripts/smoke-test-mobile.sh

```sh
#!/usr/bin/env bash
# smoke-test-mobile.sh — One-shot driver for the mobile-build-and-pair
# runbook.  Walks the operator from "phone plugged in via USB" to
# "scan this QR with the app to pair".  Stops short of the Voice
# Command smoke test because that needs ~2 GB of model downloads
# inside the phone — done manually per the runbook §B10 Test 3.
#
# Verbs:
#   ./scripts/smoke-test-mobile.sh           # full happy-path
#   ./scripts/smoke-test-mobile.sh --no-tunnel  # skip cloudflared
#                                                (useful when you have
#                                                a long-lived tunnel
#                                                in another terminal)
#
# Companion: docs/operator-runbooks/mobile-build-and-pair.md walks
# through the same flow as a human-readable story; this script
# automates the predictable parts.
#
# What it skips:
#   * Phone-side pair confirmation (the operator has to physically
#     hold the phone + tap)
#   * Voice command + model downloads
#   * Test 1 / Test 2 from the runbook (REPL data flow + WSS live-tick) —
#     wired in via § OBSERVE below

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
BRAIN_DIR="$REPO_ROOT/runtime/semantos-brain"
APP_DIR="$REPO_ROOT/apps/oddjobz-mobile"
PORT="${BRAIN_PORT:-8080}"
USE_TUNNEL=1

while [ $# -gt 0 ]; do
    case "$1" in
        --no-tunnel)
            USE_TUNNEL=0
            shift
            ;;
        --port)
            PORT="$2"
            shift 2
            ;;
        -h|--help)
            sed -n '2,25p' "$0" | sed 's/^# \{0,1\}//'
            exit 0
            ;;
        *)
            echo "smoke-test-mobile.sh: unknown arg \`$1\`" >&2
            exit 64
            ;;
    esac
done

# ── Step 0: prerequisite check (fail fast with a usable error) ──

require() {
    local bin="$1"
    local hint="$2"
    if ! command -v "$bin" &>/dev/null; then
        echo "ERROR: required tool \`$bin\` not found in PATH" >&2
        echo "       hint: $hint" >&2
        exit 1
    fi
}

require flutter "see docs/operator-runbooks/mobile-build-and-pair.md §B1"
require adb     "brew install --cask android-platform-tools"
require zig     "brew install zig (need 0.15.2)"
require bun     "brew install oven-sh/bun/bun"
if [ "$USE_TUNNEL" -eq 1 ]; then
    require cloudflared "brew install cloudflared"
fi
require qrencode "brew install qrencode (optional but nicer than the Semantos Brain ASCII QR)" || true

# ── Step 1: detect a connected phone ────────────────────────────────

devices_line=$(adb devices | awk 'NR>1 && $2=="device" {print $1; exit}')
if [ -z "$devices_line" ]; then
    echo "ERROR: no Android device with USB debugging enabled found." >&2
    echo "       run \`adb devices\` and confirm the phone shows state \`device\`" >&2
    echo "       (not \`unauthorized\`)." >&2
    echo "       See docs/operator-runbooks/mobile-build-and-pair.md §B2." >&2
    exit 1
fi
DEVICE_SERIAL="$devices_line"
echo "[smoke] phone detected:  $DEVICE_SERIAL"

# ── Step 2: build brain + native libs in parallel ─────────────────────

echo "[smoke] step 1/6 — building brain + native FFI libs"

(
    cd "$BRAIN_DIR"
    if [ ! -x "zig-out/bin/brain" ] || [ "src/cli.zig" -nt "zig-out/bin/brain" ]; then
        zig build
    else
        echo "  brain: cached"
    fi
) &
BRAIN_BUILD_PID=$!

# Skip the Android lib rebuild if CHANGES.txt is fresh (< 30 min) AND
# all 3 ABIs have a populated libsemantos.a — the operator might have
# just run scripts/build-android-libs.sh by hand.
STAGE_ROOT="$REPO_ROOT/platforms/flutter/semantos_ffi/build/android"
SKIP_LIBS=0
if [ -f "$STAGE_ROOT/CHANGES.txt" ]; then
    age_seconds=$(( $(date +%s) - $(stat -f%m "$STAGE_ROOT/CHANGES.txt" 2>/dev/null || stat -c%Y "$STAGE_ROOT/CHANGES.txt") ))
    if [ "$age_seconds" -lt 1800 ]; then
        if [ -s "$STAGE_ROOT/arm64-v8a/libsemantos.a" ] \
           && [ -s "$STAGE_ROOT/armeabi-v7a/libsemantos.a" ] \
           && [ -s "$STAGE_ROOT/x86_64/libsemantos.a" ]; then
            echo "  android libs: cached (${age_seconds}s old)"
            SKIP_LIBS=1
        fi
    fi
fi

if [ "$SKIP_LIBS" -eq 0 ]; then
    "$SCRIPT_DIR/build-android-libs.sh"
fi

wait "$BRAIN_BUILD_PID"

BRAIN_BIN="$BRAIN_DIR/zig-out/bin/brain"
[ -x "$BRAIN_BIN" ] || { echo "ERROR: brain binary missing at $BRAIN_BIN"; exit 1; }

# ── Step 3: build the APK ──────────────────────────────────────────

echo "[smoke] step 2/6 — building APK"
( cd "$APP_DIR" && flutter build apk --debug )

APK_PATH="$APP_DIR/build/app/outputs/flutter-apk/app-debug.apk"
[ -f "$APK_PATH" ] || { echo "ERROR: APK missing at $APK_PATH"; exit 1; }

# ── Step 4: start cloudflared tunnel + grab the URL ─────────────────

CLEANUP_PIDS=()
cleanup() {
    echo ""
    echo "[smoke] cleaning up background processes…"
    for pid in "${CLEANUP_PIDS[@]:-}"; do
        if [ -n "${pid:-}" ] && kill -0 "$pid" 2>/dev/null; then
            kill "$pid" 2>/dev/null || true
        fi
    done
}
trap cleanup EXIT INT TERM

if [ "$USE_TUNNEL" -eq 1 ]; then
    echo "[smoke] step 3/6 — starting cloudflared tunnel"
    TUNNEL_LOG=$(mktemp -t smoke-tunnel.XXXXXX.log)
    cloudflared tunnel --url "http://localhost:$PORT" >"$TUNNEL_LOG" 2>&1 &
    TUNNEL_PID=$!
    CLEANUP_PIDS+=("$TUNNEL_PID")

    # Wait up to 30 s for the trycloudflare URL to appear in the log.
    TUNNEL_URL=""
    for i in $(seq 1 30); do
        if grep -Eo 'https://[a-z0-9-]+\.trycloudflare\.com' "$TUNNEL_LOG" >/dev/null 2>&1; then
            TUNNEL_URL=$(grep -Eo 'https://[a-z0-9-]+\.trycloudflare\.com' "$TUNNEL_LOG" | head -1)
            break
        fi
        sleep 1
    done
    if [ -z "$TUNNEL_URL" ]; then
        echo "ERROR: cloudflared didn't print a tunnel URL after 30s" >&2
        echo "       last 20 lines of tunnel log:" >&2
        tail -20 "$TUNNEL_LOG" >&2
        exit 1
    fi
    echo "  tunnel URL: $TUNNEL_URL"
else
    TUNNEL_URL="http://localhost:$PORT"
    echo "[smoke] step 3/6 — tunnel skipped, using $TUNNEL_URL"
    echo "  WARNING: device-pair v2 requires https:// — this only works"
    echo "           if you've manually set up TLS on localhost (see"
    echo "           runbook §B5 Option 2)."
fi

# ── Step 5: start brain ──────────────────────────────────────────────

echo "[smoke] step 4/6 — starting brain on :$PORT"
BRAIN_LOG=$(mktemp -t smoke-brain.XXXXXX.log)

# Ensure init has run.
if [ ! -f "$HOME/.semantos/config.json" ]; then
    echo "  first-time brain init"
    "$BRAIN_BIN" init >>"$BRAIN_LOG" 2>&1
fi

"$BRAIN_BIN" serve localhost --port "$PORT" --enable-repl >>"$BRAIN_LOG" 2>&1 &
BRAIN_PID=$!
CLEANUP_PIDS+=("$BRAIN_PID")

# Wait for the http listener to come up (tail the log for the marker line).
for i in $(seq 1 15); do
    if grep -q "http listening" "$BRAIN_LOG" 2>/dev/null; then
        break
    fi
    sleep 1
done
if ! grep -q "http listening" "$BRAIN_LOG"; then
    echo "ERROR: brain didn't start within 15s" >&2
    tail -30 "$BRAIN_LOG" >&2
    exit 1
fi

# ── Step 6: install + launch APK ────────────────────────────────────

echo "[smoke] step 5/6 — installing APK on $DEVICE_SERIAL"
adb -s "$DEVICE_SERIAL" install -r "$APK_PATH" >/dev/null
adb -s "$DEVICE_SERIAL" shell am force-stop info.oddjobtodd.oddjobz_mobile
adb -s "$DEVICE_SERIAL" shell am start -n info.oddjobtodd.oddjobz_mobile/.MainActivity >/dev/null

# ── Step 7: mint pair token + render QR ─────────────────────────────

echo "[smoke] step 6/6 — minting 5-min pair token"
PAIR_OUTPUT=$("$BRAIN_BIN" device pair \
    --device-name "smoke-test" \
    --caps minimal \
    --brain-pair-endpoint "$TUNNEL_URL/api/v1/device-pair" \
    --brain-wss-endpoint  "$(echo "$TUNNEL_URL" | sed 's|^https://|wss://|; s|^http://|ws://|')/api/v1/wallet" \
    --qr off 2>&1) || {
        echo "ERROR: \`brain device pair\` failed:" >&2
        echo "$PAIR_OUTPUT" >&2
        exit 1
    }

PAIR_URL=$(echo "$PAIR_OUTPUT" | grep -Eo 'semantos-pair://[^[:space:]]+' | head -1)
if [ -z "$PAIR_URL" ]; then
    echo "ERROR: \`brain device pair\` succeeded but no pair URL found in its output" >&2
    echo "$PAIR_OUTPUT" >&2
    exit 1
fi

echo ""
echo "═══════════════════════════════════════════════════════"
echo "  Pair URL (5-min TTL):"
echo "  $PAIR_URL"
echo "═══════════════════════════════════════════════════════"
echo ""

if command -v qrencode &>/dev/null; then
    qrencode -t ANSIUTF8 "$PAIR_URL"
else
    echo "(install qrencode for a higher-resolution QR rendering)"
    # Fall back to brain's own --qr ascii output.
    echo "$PAIR_OUTPUT"
fi

echo ""
echo "→ open the oddjobz app on $DEVICE_SERIAL"
echo "→ tap \"Scan QR\" and point the camera at this terminal"
echo "→ confirm pairing on the phone"
echo ""
echo "After pairing, run smoke tests 1+2 from the runbook §B10:"
echo "  $ $BRAIN_BIN repl"
echo "  brain> add job --customer \"Acme Corp\" --kind lead --due 2026-05-15"
echo "  → pull-to-refresh on the phone, verify the job appears"
echo ""
echo "Tail brain log:    tail -f $BRAIN_LOG"
if [ "$USE_TUNNEL" -eq 1 ]; then
    echo "Tail tunnel log: tail -f $TUNNEL_LOG"
fi
echo "Phone logs:      adb -s $DEVICE_SERIAL logcat | grep oddjobz"
echo ""
echo "Hit Ctrl-C in this terminal to tear down brain + tunnel."
echo ""

# Hang here so the operator can drive the phone-side pair flow without
# brain + tunnel being killed by `set -e` exit.
wait "$BRAIN_PID"

```
