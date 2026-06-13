---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/inference-gate/deploy-model-to-pis.sh
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.408372+00:00
---

# cartridges/inference-gate/deploy-model-to-pis.sh

```sh
#!/usr/bin/env bash
# deploy-model-to-pis.sh — Deploy whisper.cpp inference server to Skyminer Pis
#
# Scans 192.168.0.2-20 for SSH-reachable Pis (todriguez user).
# On each reachable Pi, this script:
#   1. Installs build deps (cmake, gcc, libsdl2-dev for optional mic support)
#   2. Clones/updates whisper.cpp and builds the server + main binaries
#      (build runs in the background — takes 10-15 min on H5 ARM)
#   3. Downloads the ggml-tiny.en model (~75MB, fits in H5 2GB RAM)
#   4. Creates and enables whisper-cpp.service  — REST server on :8080
#   5. Installs bun (if not present)
#   6. Copies cell-handler.ts
#   7. Creates and enables inference-handler.service — :5196, WHISPER_URL=:8080
#
# After deploy, each Pi is a fully autonomous inference node:
#   Client → relay (cell) → handler (:5196) → whisper (:8080) → result cell
#
# USAGE
# ─────
#   ./deploy-model-to-pis.sh
#   RELAY_URL=http://192.168.0.50:5199 ./deploy-model-to-pis.sh
#   MODEL=base.en ./deploy-model-to-pis.sh          # larger model (~150MB)
#   TARGETS="192.168.0.3 192.168.0.5" ./deploy-model-to-pis.sh  # specific IPs
#
# NOTES
# ─────
# - Build is started in background via nohup; service waits for binary to exist
# - Model download requires internet access on the Pi (~75MB for tiny.en)
# - SSH key auth to todriguez@ is required (run: ssh-add ~/.ssh/id_rsa)
# - Pis must run systemd (Armbian Bookworm has it)

set -euo pipefail

# ── Config ────────────────────────────────────────────────────────────────────

RELAY_URL="${RELAY_URL:-http://192.168.20.5:5199}"
HANDLER_PORT="${HANDLER_PORT:-5196}"
WHISPER_PORT="${WHISPER_PORT:-8080}"
SSH_USER="${SSH_USER:-todriguez}"
MODEL="${MODEL:-tiny.en}"    # tiny.en (~75MB) | base.en (~150MB) | small.en (~500MB)
SSH_OPTS="-o ConnectTimeout=4 -o BatchMode=yes -o StrictHostKeyChecking=no"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HANDLER_TS="$SCRIPT_DIR/cell-handler.ts"

# Auto-derive scan subnet from RELAY_URL
_relay_host="${RELAY_URL#*://}"
_relay_host="${_relay_host%%:*}"
_relay_host="${_relay_host%%/*}"
PI_SUBNET="${PI_SUBNET:-${_relay_host%.*}}"

GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; NC='\033[0m'
ok()   { echo -e "${GREEN}  ✓${NC} $*"; }
warn() { echo -e "${YELLOW}  ⚠${NC} $*"; }
err()  { echo -e "${RED}  ✗${NC} $*"; }

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  Skyminer inference node deploy — whisper.cpp + cell-handler"
echo "  Relay:   $RELAY_URL"
echo "  Subnet:  ${TARGETS:-"$PI_SUBNET.2-20"}"
echo "  Model:   ggml-$MODEL.bin"
echo "  Ports:   whisper=:$WHISPER_PORT  handler=:$HANDLER_PORT"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

if [[ ! -f "$HANDLER_TS" ]]; then
  err "cell-handler.ts not found at $HANDLER_TS"
  exit 1
fi

FOUND=0; DEPLOYED=0; FAILED=()

# Support explicit TARGETS list or auto-scan
if [[ -n "${TARGETS:-}" ]]; then
  IPS=($TARGETS)
else
  IPS=()
  for LAST in $(seq 2 20); do IPS+=("$PI_SUBNET.$LAST"); done
fi

for IP in "${IPS[@]}"; do

  # Quick reachability probe
  if ! ssh $SSH_OPTS "$SSH_USER@$IP" "echo ok" >/dev/null 2>&1; then
    continue
  fi

  FOUND=$((FOUND + 1))
  echo ""
  echo "▸ Pi at $IP"

  # ── 1. Install build dependencies ──────────────────────────────────────────

  echo "  [1/7] installing build deps (cmake gcc g++ libsdl2-dev)…"
  ssh $SSH_OPTS "$SSH_USER@$IP" \
    "sudo apt-get update -qq && sudo apt-get install -y --no-install-recommends cmake gcc g++ make libsdl2-dev curl ca-certificates git >/dev/null 2>&1" \
    && ok "build deps installed" \
    || { err "apt-get failed on $IP — skipping"; FAILED+=("$IP"); continue; }

  # ── 2. Clone / update whisper.cpp ──────────────────────────────────────────

  echo "  [2/7] cloning whisper.cpp…"
  ssh $SSH_OPTS "$SSH_USER@$IP" "
    if [ -d ~/whisper.cpp ]; then
      cd ~/whisper.cpp && git pull --ff-only 2>/dev/null || true
    else
      git clone --depth 1 https://github.com/ggerganov/whisper.cpp.git ~/whisper.cpp
    fi
  " && ok "whisper.cpp repo ready" \
    || { err "git clone failed on $IP — skipping"; FAILED+=("$IP"); continue; }

  # ── 3. Build in background (takes 10-15 min on H5 ARM) ───────────────────
  # The service uses ConditionPathExists to wait for the binary; it restarts
  # automatically via Restart=on-failure once the binary appears.

  echo "  [3/7] starting background build (nohup, ~10-15 min on H5)…"
  ssh $SSH_OPTS "$SSH_USER@$IP" "
    cd ~/whisper.cpp
    if [ -f build/bin/server ]; then
      echo 'binary already built — skipping'
    else
      nohup bash -c 'cmake -B build -DCMAKE_BUILD_TYPE=Release >/tmp/whisper-build.log 2>&1 && cmake --build build --config Release -j4 >>/tmp/whisper-build.log 2>&1 && echo BUILD_OK >>/tmp/whisper-build.log' &
      echo \"build PID=\$! started in background\"
    fi
  " && ok "build started — tail /tmp/whisper-build.log on Pi to monitor" \
    || warn "could not start build on $IP (non-fatal)"

  # ── 4. Download model ──────────────────────────────────────────────────────

  MODEL_FILE="ggml-${MODEL}.bin"
  MODEL_URL="https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-${MODEL}.bin"
  echo "  [4/7] checking model $MODEL_FILE…"
  ssh $SSH_OPTS "$SSH_USER@$IP" "
    mkdir -p ~/whisper.cpp/models
    if [ -f ~/whisper.cpp/models/$MODEL_FILE ]; then
      echo 'model already present'
    else
      echo 'downloading $MODEL_FILE (~$([ \"$MODEL\" = \"tiny.en\" ] && echo 75 || echo 150)MB)…'
      curl -fsSL -o ~/whisper.cpp/models/$MODEL_FILE '$MODEL_URL' && echo 'download OK' || echo 'download FAILED'
    fi
  " && ok "model $MODEL_FILE ready" \
    || warn "model download may have failed — check on $IP"

  # ── 5. Write whisper-cpp.service ───────────────────────────────────────────

  echo "  [5/7] writing whisper-cpp.service (:$WHISPER_PORT)…"
  ssh $SSH_OPTS "$SSH_USER@$IP" "sudo tee /etc/systemd/system/whisper-cpp.service > /dev/null" <<EOF
[Unit]
Description=whisper.cpp REST inference server (:$WHISPER_PORT)
After=network.target
ConditionPathExists=/home/$SSH_USER/whisper.cpp/build/bin/server

[Service]
Type=simple
User=$SSH_USER
WorkingDirectory=/home/$SSH_USER/whisper.cpp
ExecStart=/home/$SSH_USER/whisper.cpp/build/bin/server \\
  --model /home/$SSH_USER/whisper.cpp/models/$MODEL_FILE \\
  --host 0.0.0.0 \\
  --port $WHISPER_PORT \\
  --threads 4 \\
  --language en
Restart=on-failure
RestartSec=10
Environment=HOME=/home/$SSH_USER

[Install]
WantedBy=multi-user.target
EOF
  ok "whisper-cpp.service written"

  # ── 6. Install bun + copy cell-handler.ts ─────────────────────────────────

  echo "  [6/7] installing bun + cell-handler.ts…"
  if ! ssh $SSH_OPTS "$SSH_USER@$IP" "command -v bun" >/dev/null 2>&1; then
    echo "    installing bun (requires internet)…"
    ssh $SSH_OPTS "$SSH_USER@$IP" \
      "curl -fsSL https://bun.sh/install | bash" >/dev/null 2>&1 \
      || { err "bun install failed on $IP"; FAILED+=("$IP"); continue; }
  else
    BV=$(ssh $SSH_OPTS "$SSH_USER@$IP" "bun --version 2>/dev/null || echo ?")
    ok "bun $BV already installed"
  fi

  ssh $SSH_OPTS "$SSH_USER@$IP" "mkdir -p ~/inference-handler"
  scp -q $SSH_OPTS "$HANDLER_TS" "$SSH_USER@$IP:~/inference-handler/cell-handler.ts"
  ok "cell-handler.ts copied"

  # ── 7. Write inference-handler.service ────────────────────────────────────

  echo "  [7/7] writing inference-handler.service (:$HANDLER_PORT)…"
  ssh $SSH_OPTS "$SSH_USER@$IP" "sudo tee /etc/systemd/system/inference-handler.service > /dev/null" <<EOF
[Unit]
Description=Inference Gate cell handler (:$HANDLER_PORT)
After=network.target whisper-cpp.service

[Service]
Type=simple
User=$SSH_USER
WorkingDirectory=/home/$SSH_USER/inference-handler
ExecStart=/home/$SSH_USER/.bun/bin/bun cell-handler.ts
Restart=on-failure
RestartSec=5
Environment=HOME=/home/$SSH_USER
Environment=RELAY_URL=$RELAY_URL
Environment=CELL_HANDLER_PORT=$HANDLER_PORT
Environment=WHISPER_URL=http://127.0.0.1:$WHISPER_PORT
Environment=HANDLER_NAME=inference-pi-$IP

[Install]
WantedBy=multi-user.target
EOF
  ok "inference-handler.service written"

  # Enable both services
  ssh $SSH_OPTS "$SSH_USER@$IP" "
    sudo systemctl daemon-reload
    sudo systemctl enable whisper-cpp --now 2>/dev/null || true
    sudo systemctl enable inference-handler --now
  " >/dev/null 2>&1

  sleep 1
  HANDLER_STATUS=$(ssh $SSH_OPTS "$SSH_USER@$IP" "systemctl is-active inference-handler 2>/dev/null || echo unknown")
  WHISPER_STATUS=$(ssh $SSH_OPTS "$SSH_USER@$IP" "systemctl is-active whisper-cpp 2>/dev/null || echo waiting")

  ok "inference-handler: $HANDLER_STATUS"
  if [[ "$WHISPER_STATUS" == "active" ]]; then
    ok "whisper-cpp: active"
  else
    warn "whisper-cpp: $WHISPER_STATUS (binary still building — service restarts when ready)"
    echo "    Monitor: ssh $SSH_USER@$IP 'tail -f /tmp/whisper-build.log'"
  fi

  DEPLOYED=$((DEPLOYED + 1))
done

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  Done."
echo "  Found:    $FOUND Pis"
echo "  Deployed: $DEPLOYED"
if [[ ${#FAILED[@]} -gt 0 ]]; then
  echo "  Failed:   ${FAILED[*]}"
fi
echo ""
echo "  Each deployed Pi:"
echo "    :$WHISPER_PORT  whisper.cpp REST  (POST /inference  file=@audio.wav)"
echo "    :$HANDLER_PORT  cell-handler      (inference.request.* → inference.result.response)"
echo ""
echo "  Check a Pi:"
echo "    curl http://<pi-ip>:$HANDLER_PORT/health"
echo "    curl http://<pi-ip>:$HANDLER_PORT/stats"
echo "    curl http://<pi-ip>:$HANDLER_PORT/log"
echo ""
echo "  Monitor build (if still running):"
echo "    ssh $SSH_USER@<pi-ip> 'tail -f /tmp/whisper-build.log'"
echo ""
echo "  Once build completes, whisper-cpp activates automatically."
echo "  Test an inference round-trip from this machine:"
echo "    RELAY_URL=$RELAY_URL bun cartridges/inference-gate/infer-client.ts \"fire alarm zone 3\""
echo ""
echo "  To use real audio via a Pi microphone:"
echo "    bun cartridges/inference-gate/mic-to-cell.ts --relay $RELAY_URL"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

```
