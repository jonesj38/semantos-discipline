---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/inference-gate/scripts/setup-llama-rpc-worker.sh
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.417835+00:00
---

# cartridges/inference-gate/scripts/setup-llama-rpc-worker.sh

```sh
#!/usr/bin/env bash
# setup-llama-rpc-worker.sh
#
# Sets up a Skyminer Orange Pi Prime (H5/aarch64, Armbian) as a specialised
# llama.cpp inference worker in the Semantos mesh.
#
# What it does:
#   1. Installs bun if not present
#   2. Downloads llama.cpp aarch64 binary (pre-built from GitHub releases)
#   3. Downloads Llama 3.2 1B Q4_K_M from HuggingFace (~700MB)
#   4. Starts llama-server on a local port
#   5. Starts worker-handler.ts connected to the relay + registry
#   6. Creates systemd units for both, enabled at boot
#
# Usage:
#   ./setup-llama-rpc-worker.sh --pi-index 1 --coordinator-ip 192.168.0.100
#   ./setup-llama-rpc-worker.sh --pi-index 2 --coordinator-ip 192.168.0.100 --model llama-3b
#
# Pi specialisation by index:
#   1 → inference.safety.*   (PPE, fire, fall, emergency)
#   2 → inference.analysis.* (anomaly, sensor, report)
#   3 → inference.access.*   (policy gate, cert tier)
#   4 → inference.ppe.*      (PPE-specific, detailed)
#   5 → inference.vision.*   (YOLO, object detection)
#   6 → inference.audio.*    (whisper, speech-to-text)
#   7 → inference.bgp.*      (BGP/IXP routing analysis)
#   8 → inference.*          (general fallback)
#
# Tested on: Armbian 23.x, aarch64, Orange Pi Prime H5
# NOT tested: Orange Pi OS, Raspberry Pi OS (different paths)

set -euo pipefail

# ── Defaults ─────────────────────────────────────────────────────────────────
PI_INDEX=1
COORDINATOR_IP="192.168.0.100"
MODEL="llama-1b"
RELAY_PORT=5199
REGISTRY_PORT=5201
LLAMA_PORT=8080
WORKER_PORT=5196
INSTALL_DIR="/opt/semantos"
LLAMA_RELEASE="b9357"   # llama.cpp release tag — repo moved to ggml-org/llama.cpp
HF_REPO="bartowski/Llama-3.2-1B-Instruct-GGUF"
HF_FILE_1B="Llama-3.2-1B-Instruct-Q4_K_M.gguf"
HF_FILE_3B="Llama-3.2-3B-Instruct-Q4_K_M.gguf"
HF_REPO_3B="bartowski/Llama-3.2-3B-Instruct-GGUF"

# ── Arg parsing ───────────────────────────────────────────────────────────────
while [[ $# -gt 0 ]]; do
  case "$1" in
    --pi-index)       PI_INDEX="$2";       shift 2 ;;
    --coordinator-ip) COORDINATOR_IP="$2"; shift 2 ;;
    --model)          MODEL="$2";          shift 2 ;;
    --relay-port)     RELAY_PORT="$2";     shift 2 ;;
    --registry-port)  REGISTRY_PORT="$2";  shift 2 ;;
    --install-dir)    INSTALL_DIR="$2";    shift 2 ;;
    --help|-h)
      sed -n '/^#/p' "$0" | head -40 | sed 's/^# \?//'
      exit 0 ;;
    *) echo "Unknown arg: $1" >&2; exit 1 ;;
  esac
done

RELAY_URL="http://${COORDINATOR_IP}:${RELAY_PORT}"
REGISTRY_URL="http://${COORDINATOR_IP}:${REGISTRY_PORT}"
NODE_IP=$(hostname -I | awk '{print $1}')

# ── Specialisation map ────────────────────────────────────────────────────────
case "$PI_INDEX" in
  1) WORKER_TYPES="inference.safety.*"   ; SPECIALTY="safety"   ;;
  2) WORKER_TYPES="inference.analysis.*" ; SPECIALTY="analysis"  ;;
  3) WORKER_TYPES="inference.access.*"   ; SPECIALTY="access"    ;;
  4) WORKER_TYPES="inference.ppe.*"      ; SPECIALTY="ppe"       ;;
  5) WORKER_TYPES="inference.vision.*"   ; SPECIALTY="vision"    ;;
  6) WORKER_TYPES="inference.audio.*"    ; SPECIALTY="audio"     ;;
  7) WORKER_TYPES="inference.bgp.*"      ; SPECIALTY="bgp"       ;;
  8) WORKER_TYPES="inference.*"          ; SPECIALTY="general"   ;;
  *) WORKER_TYPES="inference.*"          ; SPECIALTY="general"   ;;
esac

echo "══════════════════════════════════════════════════════════"
echo "  Semantos Mesh Inference Worker Setup"
echo "  Pi index:     $PI_INDEX ($SPECIALTY specialist)"
echo "  Worker types: $WORKER_TYPES"
echo "  Coordinator:  $COORDINATOR_IP"
echo "  Node IP:      $NODE_IP"
echo "  Model:        $MODEL"
echo "══════════════════════════════════════════════════════════"

# ── 1. Install bun ────────────────────────────────────────────────────────────
if ! command -v bun &>/dev/null; then
  echo "[setup] Installing bun..."
  curl -fsSL https://bun.sh/install | bash
  export PATH="$HOME/.bun/bin:$PATH"
  echo 'export PATH="$HOME/.bun/bin:$PATH"' >> ~/.bashrc
fi
echo "[setup] bun: $(bun --version)"

# ── 2. Create install directory ───────────────────────────────────────────────
mkdir -p "$INSTALL_DIR"/{bin,models,src}

# ── 3. Download llama.cpp aarch64 binary ──────────────────────────────────────
LLAMA_BIN="$INSTALL_DIR/bin/llama-server"
if [[ ! -f "$LLAMA_BIN" ]]; then
  echo "[setup] Downloading llama.cpp ${LLAMA_RELEASE} for aarch64..."
  # Repo moved to ggml-org; tar.gz format with shared libs
  LLAMA_URL="https://github.com/ggml-org/llama.cpp/releases/download/${LLAMA_RELEASE}/llama-${LLAMA_RELEASE}-bin-ubuntu-arm64.tar.gz"
  cd /tmp
  wget -q --show-progress "$LLAMA_URL" -O llama-aarch64.tar.gz
  mkdir -p llama-aarch64
  tar -xzf llama-aarch64.tar.gz -C llama-aarch64/ 2>/dev/null || true
  # All files (binary + shared libs) go to bin dir
  find llama-aarch64/ -maxdepth 2 \( -name 'llama-server' -o -name '*.so*' \) -exec cp -P {} "$INSTALL_DIR/bin/" \;
  chmod +x "$INSTALL_DIR/bin/llama-server"
  rm -rf llama-aarch64 llama-aarch64.tar.gz
  cd -
fi
echo "[setup] llama-server: $LLAMA_BIN"

# ── 4. Download model ─────────────────────────────────────────────────────────
if [[ "$MODEL" == "llama-3b" ]]; then
  MODEL_FILE="$INSTALL_DIR/models/$HF_FILE_3B"
  HF_DOWNLOAD_URL="https://huggingface.co/${HF_REPO_3B}/resolve/main/${HF_FILE_3B}"
else
  MODEL_FILE="$INSTALL_DIR/models/$HF_FILE_1B"
  HF_DOWNLOAD_URL="https://huggingface.co/${HF_REPO}/resolve/main/${HF_FILE_1B}"
fi

if [[ ! -f "$MODEL_FILE" ]]; then
  echo "[setup] Downloading model (~$([ "$MODEL" = "llama-3b" ] && echo "1.9GB" || echo "700MB"))..."
  wget -q --show-progress "$HF_DOWNLOAD_URL" -O "$MODEL_FILE"
fi
echo "[setup] Model: $MODEL_FILE ($(du -sh "$MODEL_FILE" | cut -f1))"

# ── 5. Copy worker-handler.ts ─────────────────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cp "$SCRIPT_DIR/../worker-handler.ts" "$INSTALL_DIR/src/worker-handler.ts"
echo "[setup] Copied worker-handler.ts to $INSTALL_DIR/src/"

# ── 6. Create systemd unit: llama-server ──────────────────────────────────────
cat > /tmp/semantos-llama.service <<UNIT
[Unit]
Description=Semantos llama.cpp inference server (Pi ${PI_INDEX})
After=network.target
Wants=network-online.target

[Service]
Type=simple
User=${USER}
WorkingDirectory=${INSTALL_DIR}
Environment="LD_LIBRARY_PATH=${INSTALL_DIR}/bin"
ExecStart=${LLAMA_BIN} \\
  --model ${MODEL_FILE} \\
  --port ${LLAMA_PORT} \\
  --host 127.0.0.1 \\
  --threads 4 \\
  --ctx-size 2048 \\
  --n-predict 256 \\
  --no-mmap
Restart=always
RestartSec=5
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
UNIT
sudo cp /tmp/semantos-llama.service /etc/systemd/system/
echo "[setup] Created semantos-llama.service"

# ── 7. Create systemd unit: worker-handler ────────────────────────────────────
BUN_PATH=$(command -v bun || echo "$HOME/.bun/bin/bun")
cat > /tmp/semantos-worker.service <<UNIT
[Unit]
Description=Semantos mesh inference worker (Pi ${PI_INDEX} — ${SPECIALTY})
After=network.target semantos-llama.service

[Service]
Type=simple
User=${USER}
WorkingDirectory=${INSTALL_DIR}/src
Environment="WORKER_TYPES=${WORKER_TYPES}"
Environment="MODEL=${MODEL}"
Environment="NODE_IP=${NODE_IP}"
Environment="RELAY_URL=${RELAY_URL}"
Environment="REGISTRY_URL=${REGISTRY_URL}"
Environment="LLAMA_URL=http://127.0.0.1:${LLAMA_PORT}"
Environment="WORKER_PORT=${WORKER_PORT}"
Environment="MAX_CONCURRENT=2"
ExecStart=${BUN_PATH} worker-handler.ts
Restart=always
RestartSec=5
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
UNIT
sudo cp /tmp/semantos-worker.service /etc/systemd/system/
echo "[setup] Created semantos-worker.service"

# ── 8. Enable + start services ────────────────────────────────────────────────
sudo systemctl daemon-reload
sudo systemctl enable semantos-llama semantos-worker
sudo systemctl start semantos-llama

echo "[setup] Waiting for llama-server to start..."
for i in $(seq 1 30); do
  if curl -s "http://127.0.0.1:${LLAMA_PORT}/health" &>/dev/null; then
    echo "[setup] llama-server ready"
    break
  fi
  sleep 2
done

sudo systemctl start semantos-worker

# ── 9. Verify ─────────────────────────────────────────────────────────────────
sleep 2
echo ""
echo "══════════════════════════════════════════════════════════"
echo "  Setup complete!"
echo ""
echo "  Services:"
systemctl is-active semantos-llama && echo "  ✓ semantos-llama (llama-server :${LLAMA_PORT})"
systemctl is-active semantos-worker && echo "  ✓ semantos-worker (worker-handler :${WORKER_PORT})"
echo ""
echo "  Worker health:"
curl -s "http://127.0.0.1:${WORKER_PORT}/health" | python3 -m json.tool 2>/dev/null || echo "  (not yet responding)"
echo ""
echo "  View logs:"
echo "    journalctl -u semantos-worker -f"
echo "    journalctl -u semantos-llama -f"
echo ""
echo "  Check registry from coordinator:"
echo "    curl http://${COORDINATOR_IP}:${REGISTRY_PORT}/workers"
echo "══════════════════════════════════════════════════════════"

```
