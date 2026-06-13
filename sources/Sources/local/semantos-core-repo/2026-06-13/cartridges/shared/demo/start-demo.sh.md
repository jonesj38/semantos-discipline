---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/shared/demo/start-demo.sh
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.436016+00:00
---

# cartridges/shared/demo/start-demo.sh

```sh
#!/usr/bin/env bash
# start-demo.sh — One-command Layer Collapse demo launcher
#
# Starts all four local services needed for the full Compute → Network →
# Storage → Money pipeline demo and opens the IXP dashboard in the browser.
#
# Usage:
#   bash cartridges/shared/demo/start-demo.sh            # demo mode (no BSV required)
#   TICK_RATE=5 bash cartridges/shared/demo/start-demo.sh
#   FUNDED=true bash cartridges/shared/demo/start-demo.sh             # MND x402 (~7s/settle, 50MB/cycle)
#   FUNDED=true AUTO_SETTLE_SECS=120 bash ...                         # MND, settle at most every 2 min
#   HEADLESS_WALLET=true bash cartridges/shared/demo/start-demo.sh    # headless wallet (~100ms/settle)
#
# TypeHash segment routing fuzzer (run in a separate terminal after demo starts):
#   bun cartridges/shared/demo/type-fuzzer.ts                         # 50 cells/sec, infinite
#   FUZZ_RATE=200 bun cartridges/shared/demo/type-fuzzer.ts           # 200 cells/sec
#   FUZZ_RATE=500 FUZZ_SECS=10 bun cartridges/shared/demo/type-fuzzer.ts  # 10s burst
#   Fuzzes all 4,096 type paths (8×8×8×8) with canonical (8|8|8|8) typeHash
#   Watch the "TypeHash Routing" panel in any dashboard for live priority routing
#
# Settlement modes:
#   Default (DEMO_MODE):    no real BSV — demonstrates pipeline without payments
#   FUNDED=true:            Metanet Desktop at :3321 required; 2 createAction per settlement (~7s)
#   HEADLESS_WALLET=true:   self-contained BSV wallet — direct sign + ARC (~100ms per settlement)
#                           Set BRIDGE_WALLET_KEY=<64-hex> or fund the auto-generated address.
#                           Test the EF tx builder first: bun cartridges/shared/anchor/test-headless-wallet.ts
#
# Services started:
#   :5190  python3 http.server  — static dashboard files
#   :5199  multicast-relay.ts  — SRv6 relay (RELAY_ALLOW_LOCAL_INJECT=true)
#   :5197  cell-store.ts       — SQLite cell persistence
#   :5198  cashlanes-bridge.ts — CashLanes x402 bridge (optional, graceful if missing)
#   :5196  cell-handler.ts     — Inference Gate cell handler (mock/whisper/ollama)
#   --     cell-injector.ts    — MNCA Compute Layer (DEMO_MODE=true)
#
# Inference cell handler modes (set before starting):
#   Default:                mock keyword classifier — no model required
#   WHISPER_URL=http://localhost:8080  proxy to whisper.cpp (real ASR)
#   OLLAMA_URL=http://localhost:11434  proxy to Ollama (real LLM)
#
# Send a test inference request (after demo starts):
#   bun cartridges/inference-gate/infer-client.ts "hard hat missing in zone 3"
#   bun cartridges/inference-gate/infer-client.ts --loop 10   # 10 random prompts
#
# Press Ctrl+C to stop all services.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
cd "$REPO_ROOT"

TICK_RATE="${TICK_RATE:-10}"
FUNDED="${FUNDED:-false}"
RESET="${RESET:-false}"
HEADLESS_WALLET="${HEADLESS_WALLET:-false}"

# --reset flag: wipe cell-store DB for a clean demo start
if [ "$RESET" = "true" ] || [ "${1:-}" = "--reset" ]; then
  echo "  Resetting cell-store DB…"
  rm -f cell-store.sqlite && echo "  Deleted cell-store.sqlite"
fi

# ── Colour helpers ─────────────────────────────────────────────────────────────
GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; NC='\033[0m'
ok()   { echo -e "${GREEN}  ✓${NC} $*"; }
warn() { echo -e "${YELLOW}  ⚠${NC} $*"; }
err()  { echo -e "${RED}  ✗${NC} $*"; }
sep()  { echo -e "\n${YELLOW}────────────────────────────────────────────────${NC}"; }

# ── Prerequisite checks ────────────────────────────────────────────────────────
sep
echo "  Layer Collapse Demo — starting services"
sep

if ! command -v bun &>/dev/null; then
  err "bun not found — install from https://bun.sh"; exit 1
fi
if ! command -v python3 &>/dev/null; then
  err "python3 not found"; exit 1
fi
ok "bun $(bun --version)  python3 $(python3 --version 2>&1 | cut -d' ' -f2)"

# ── Kill stale processes ───────────────────────────────────────────────────────
pkill -f 'bun.*multicast-relay'  2>/dev/null && warn "killed stale relay"   || true
pkill -f 'bun.*cell-store'       2>/dev/null && warn "killed stale cell-store" || true
pkill -f 'bun.*cell-injector'    2>/dev/null && warn "killed stale injector" || true
pkill -f 'bun.*cashlanes-bridge' 2>/dev/null && warn "killed stale bridge"  || true
pkill -f 'bun.*cell-handler'     2>/dev/null && warn "killed stale cell-handler" || true
pkill -f 'python3.*5190'         2>/dev/null && warn "killed stale http server" || true
sleep 1

# ── PID tracking ──────────────────────────────────────────────────────────────
PIDS=()

cleanup() {
  echo ""
  warn "Stopping all demo services…"
  for pid in "${PIDS[@]}"; do
    kill "$pid" 2>/dev/null || true
  done
  wait 2>/dev/null || true
  echo "  Done."
}
trap cleanup EXIT INT TERM

# ── Start: static server (:5190) ──────────────────────────────────────────────
python3 -m http.server 5190 --directory cartridges > /tmp/demo-http.log 2>&1 &
PIDS+=($!)
ok "Static server     :5190  (cartridges/)"

# ── Start: multicast relay (:5199) ────────────────────────────────────────────
RELAY_ALLOW_LOCAL_INJECT=true \
  bun cartridges/shared/relay/multicast-relay.ts > /tmp/demo-relay.log 2>&1 &
PIDS+=($!)
ok "Relay             :5199  RELAY_ALLOW_LOCAL_INJECT=true"

# ── Start: CashLanes bridge (:5198) — optional ────────────────────────────────
# AUTO_SETTLE_MB default is 50 (bridge code). For MND mode add AUTO_SETTLE_SECS=120
# to ensure settlements happen at most every 2 min regardless of cell throughput.
HEADLESS_WALLET="$HEADLESS_WALLET" AUTO_SETTLE_SECS="${AUTO_SETTLE_SECS:-}" \
  bun cartridges/shared/relay/cashlanes-bridge.ts > /tmp/demo-bridge.log 2>&1 &
PIDS+=($!)
sleep 1.5
if curl -sf http://localhost:5198/channel/state >/dev/null 2>&1; then
  if [ "$HEADLESS_WALLET" = "true" ]; then
    WALLET_ADDR=$(curl -sf http://localhost:5198/health 2>/dev/null | grep -o '"walletAddress":"[^"]*"' | cut -d'"' -f4 || echo "")
    ok "CashLanes bridge  :5198  headless wallet mode (~100ms/settlement)${WALLET_ADDR:+  addr=$WALLET_ADDR}"
  else
    ok "CashLanes bridge  :5198  (Metanet Desktop :3321 required for real x402)"
  fi
else
  warn "CashLanes bridge not responding — relay allows demo publishes without x402"
fi

# ── Start: cell-store (:5197) ─────────────────────────────────────────────────
sleep 1
bun cartridges/shared/cell-store/cell-store.ts > /tmp/demo-cell-store.log 2>&1 &
PIDS+=($!)
ok "Cell store        :5197  SQLite ./cell-store.sqlite"

# ── Wait for relay to be ready ────────────────────────────────────────────────
echo ""
echo "  Waiting for relay…"
for i in $(seq 1 10); do
  if curl -sf http://localhost:5199/health >/dev/null 2>&1; then
    ok "Relay online"; break
  fi
  sleep 0.5
  if [ "$i" -eq 10 ]; then
    err "Relay did not come up in 5s — check /tmp/demo-relay.log"; exit 1
  fi
done

# ── Start: MNCA cell injector ─────────────────────────────────────────────────
if [ "$FUNDED" = "true" ]; then
  warn "FUNDED mode — waiting for FLOW_ACTIVE channel before injection"
  TICK_RATE="$TICK_RATE" \
    bun cartridges/shared/demo/cell-injector.ts > /tmp/demo-injector.log 2>&1 &
else
  DEMO_MODE=true TICK_RATE="$TICK_RATE" \
    bun cartridges/shared/demo/cell-injector.ts > /tmp/demo-injector.log 2>&1 &
fi
PIDS+=($!)
DEMO_LABEL="true"; [ "$FUNDED" = "true" ] && DEMO_LABEL="false"
ok "MNCA injector              DEMO_MODE=$DEMO_LABEL  TICK_RATE=$TICK_RATE/s"

# ── Start: policy simulator (fires infra-demo events at 0.3 events/sec) ───────
bun cartridges/shared/demo/policy-simulator.ts > /tmp/demo-policy-sim.log 2>&1 &
PIDS+=($!)
ok "Policy simulator           0.3 events/sec  (6 infra-demo event types)"

# ── Start: inference cell handler (:5196) ─────────────────────────────────────
WHISPER_URL="${WHISPER_URL:-}" OLLAMA_URL="${OLLAMA_URL:-}" \
  bun cartridges/inference-gate/cell-handler.ts > /tmp/demo-cell-handler.log 2>&1 &
PIDS+=($!)
sleep 1
if curl -sf http://localhost:5196/health >/dev/null 2>&1; then
  MODEL_LABEL=$(curl -sf http://localhost:5196/health 2>/dev/null | grep -o '"model":"[^"]*"' | cut -d'"' -f4 || echo "mock")
  ok "Inference handler  :5196  model=$MODEL_LABEL"
else
  warn "Inference handler not responding — check /tmp/demo-cell-handler.log"
fi

# ── Summary ────────────────────────────────────────────────────────────────────
sep
echo ""
echo "  Layer Collapse Demo is LIVE"
echo ""
echo "  IXP routing:   http://localhost:5190/ixp-routing/verify/index.html"
echo "  Dark fiber:    http://localhost:5190/dark-fiber/verify/index.html"
echo "  Inference gate:http://localhost:5190/inference-gate/verify/index.html"
echo ""
echo "  Logs:  /tmp/demo-relay.log  /tmp/demo-cell-store.log  /tmp/demo-injector.log  /tmp/demo-cell-handler.log"
echo ""
echo "  Inference round-trip (run in a separate terminal — handler is already running):"
echo "    bun cartridges/inference-gate/infer-client.ts \"hard hat missing in zone 3\""
echo "    bun cartridges/inference-gate/infer-client.ts --loop 10   # 10 random prompts"
echo "    WHISPER_URL=http://localhost:8080 bun ... --model whisper  # real ASR"
echo "    OLLAMA_URL=http://localhost:11434 bun ... --model llm      # real LLM"
echo ""
echo "  TypeHash fuzzer (run in a separate terminal to stress-test routing):"
echo "    bun cartridges/shared/demo/type-fuzzer.ts                         # 50/s, infinite"
echo "    FUZZ_RATE=500 FUZZ_SECS=10 bun cartridges/shared/demo/type-fuzzer.ts  # 10s burst"
echo "    Populates the TypeHash Routing Table panel in all dashboards."
echo ""
if [ "$HEADLESS_WALLET" = "true" ]; then
  WALLET_ADDR=$(curl -sf http://localhost:5198/health 2>/dev/null | grep -o '"walletAddress":"[^"]*"' | cut -d'"' -f4 || echo "")
  WALLET_BAL=$(curl -sf http://localhost:5198/health 2>/dev/null | grep -o '"walletBalance":"[^"]*"' | cut -d'"' -f4 || echo "unknown")
  ok "Headless wallet mode (~100ms/settlement, direct ARC broadcast)"
  echo "    Balance: $WALLET_BAL${WALLET_ADDR:+  Address: $WALLET_ADDR}"
  if [ -n "$WALLET_ADDR" ]; then
    echo "    Fund with BSV: send to $WALLET_ADDR"
    echo "    Or set BRIDGE_WALLET_KEY=<64-hex> to load a pre-funded key."
  fi
elif [ "$FUNDED" != "true" ]; then
  warn "Channel not required in DEMO_MODE.  To enable real x402 payments:"
  echo "    Metanet Desktop: FUNDED=true bash start-demo.sh  (requires MND :3321, ~7s/settle)"
  echo "    Headless wallet: HEADLESS_WALLET=true bash start-demo.sh  (~100ms/settle)"
  echo "      1. Start with HEADLESS_WALLET=true — note the wallet address printed"
  echo "      2. Fund that address with BSV (any amount ≥ 50k sats for 40+ settlements)"
  echo "      3. Restart — settlements go on-chain at ~100ms each"
fi
echo ""
echo "  Press Ctrl+C to stop all services."
sep

# ── Open browser (macOS / Linux) ──────────────────────────────────────────────
sleep 1
if command -v open &>/dev/null; then
  open "http://localhost:5190/ixp-routing/verify/index.html"
elif command -v xdg-open &>/dev/null; then
  xdg-open "http://localhost:5190/ixp-routing/verify/index.html"
fi

# ── Tail injector log so user can see MNCA output ─────────────────────────────
echo ""
tail -f /tmp/demo-injector.log &
PIDS+=($!)

wait

```
