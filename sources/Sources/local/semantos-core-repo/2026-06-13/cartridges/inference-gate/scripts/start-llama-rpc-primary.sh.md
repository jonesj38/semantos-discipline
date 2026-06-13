---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/inference-gate/scripts/start-llama-rpc-primary.sh
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.417548+00:00
---

# cartridges/inference-gate/scripts/start-llama-rpc-primary.sh

```sh
#!/usr/bin/env bash
# start-llama-rpc-primary.sh
#
# Configures Pi #1 to run llama-server with llama.cpp RPC backends.
# Run this AFTER setup-rpc-server.sh has started rpc-server
# on Pi #2, #3, #4 (or however many you've set up).
#
# Usage:
#   ./start-llama-rpc-primary.sh
#   ./start-llama-rpc-primary.sh --rpc-backends "192.168.0.3:5205,192.168.0.4:5205"
#   ./start-llama-rpc-primary.sh --model llama-7b  # use 7B model
#   ./start-llama-rpc-primary.sh --model llama-1b  # use 1B model (default, for testing)
#
# Model sizes and RAM requirements (Q4_K_M):
#   llama-1b:  Llama-3.2-1B-Instruct  ~0.8GB  (fits on Pi #1 alone, RPC optional)
#   llama-3b:  Llama-3.2-3B-Instruct  ~1.9GB  (fits on Pi #1, RPC helps with throughput)
#   llama-7b:  Llama-3.1-7B-Instruct  ~4.2GB  (REQUIRES 3+ RPC backends, ~1.4GB each)
#
# With 3 RPC backends (Pi #2, #3, #4), Pi #1 holds the coordinator + some layers,
# backends hold the rest. Total: ~5.6GB capacity across 4 Pis × 2GB RAM.
#
# Download 7B model (laptop, then SCP to Pi #1):
#   huggingface-cli download bartowski/Meta-Llama-3.1-8B-Instruct-GGUF \
#     Meta-Llama-3.1-8B-Instruct-Q4_K_M.gguf --local-dir ./models/
#   scp ./models/Meta-Llama-3.1-8B-Instruct-Q4_K_M.gguf \
#     todriguez@192.168.20.8:/opt/semantos/models/
#
# Or 3B (faster, fits on 1 Pi):
#   huggingface-cli download bartowski/Llama-3.2-3B-Instruct-GGUF \
#     Llama-3.2-3B-Instruct-Q4_K_M.gguf --local-dir ./models/

set -euo pipefail

# ── Defaults ──────────────────────────────────────────────────────────────────
SSH_USER="todriguez"
SSH_KEY="${HOME}/.ssh/id_ed25519"
SSH_OPTS="-o StrictHostKeyChecking=no -o ConnectTimeout=8 -o BatchMode=yes"
JUMP_HOST="192.168.20.8"         # Pi #1 wlan0 (direct SSH from laptop)
BINARY_DIR="/opt/semantos/bin"
MODEL_DIR="/opt/semantos/models"
MODEL="llama-1b"
RPC_BACKENDS=""
LLAMA_PORT=8080
CTX_SIZE=2048
THREADS=4

declare -A MODEL_FILES=(
  ["llama-1b"]="Llama-3.2-1B-Instruct-Q4_K_M.gguf"
  ["llama-3b"]="Llama-3.2-3B-Instruct-Q4_K_M.gguf"
  ["llama-7b"]="Meta-Llama-3.1-8B-Instruct-Q4_K_M.gguf"
)

# ── Arg parsing ───────────────────────────────────────────────────────────────
while [[ $# -gt 0 ]]; do
  case "$1" in
    --rpc-backends) RPC_BACKENDS="$2"; shift 2 ;;
    --model)        MODEL="$2";        shift 2 ;;
    --port)         LLAMA_PORT="$2";   shift 2 ;;
    --ctx-size)     CTX_SIZE="$2";     shift 2 ;;
    --threads)      THREADS="$2";      shift 2 ;;
    --ssh-key)      SSH_KEY="$2";      shift 2 ;;
    --ssh-user)     SSH_USER="$2";     shift 2 ;;
    --jump-host)    JUMP_HOST="$2";    shift 2 ;;
    --help|-h)
      sed -n '/^#/p' "$0" | head -50 | sed 's/^# \?//'
      exit 0 ;;
    *) echo "Unknown arg: $1" >&2; exit 1 ;;
  esac
done

SSH_ID="-i ${SSH_KEY}"
RED='\033[0;31m'; GRN='\033[0;32m'; YLW='\033[0;33m'; BLU='\033[0;34m'; RST='\033[0m'

MODEL_FILE="${MODEL_FILES[$MODEL]:-${MODEL_FILES[llama-1b]}}"

echo ""
echo -e "${BLU}══════════════════════════════════════════════════════${RST}"
echo -e "${BLU}  Start Llama RPC Primary (Pi #1)${RST}"
echo -e "  Model:    ${MODEL} → ${MODEL_FILE}"
echo -e "  Backends: ${RPC_BACKENDS:-"(none — single-Pi mode)"}"
echo -e "  Port:     ${LLAMA_PORT}"
echo -e "${BLU}══════════════════════════════════════════════════════${RST}"
echo ""

# ── Check model file ──────────────────────────────────────────────────────────
echo "Checking model on Pi #1..."
if ssh ${SSH_ID} ${SSH_OPTS} "${SSH_USER}@${JUMP_HOST}" \
    "test -f ${MODEL_DIR}/${MODEL_FILE} && echo ok" 2>/dev/null | grep -q ok; then
  echo -e "  ${GRN}✓${RST} Model found: ${MODEL_DIR}/${MODEL_FILE}"
else
  echo -e "  ${RED}✗${RST} Model NOT found: ${MODEL_DIR}/${MODEL_FILE}"
  echo ""
  echo "  Download on laptop then SCP:"
  echo "    huggingface-cli download bartowski/${MODEL_FILE%%-Q4*}-GGUF ${MODEL_FILE} --local-dir ./models/"
  echo "    scp ./models/${MODEL_FILE} ${SSH_USER}@${JUMP_HOST}:${MODEL_DIR}/"
  echo ""
  if [[ "$MODEL" == "llama-1b" ]]; then
    echo "  Checking for any available model..."
    AVAIL=$(ssh ${SSH_ID} ${SSH_OPTS} "${SSH_USER}@${JUMP_HOST}" "ls ${MODEL_DIR}/*.gguf 2>/dev/null | head -3" 2>/dev/null || echo "")
    if [[ -n "$AVAIL" ]]; then
      echo -e "  Found: ${AVAIL}"
      MODEL_FILE=$(basename "$(echo "$AVAIL" | head -1)")
      echo -e "  ${YLW}Using ${MODEL_FILE} instead${RST}"
    else
      echo -e "  ${RED}No .gguf models found. Aborting.${RST}"
      exit 1
    fi
  else
    exit 1
  fi
fi

# ── Verify RPC backends (if any) ──────────────────────────────────────────────
if [[ -n "$RPC_BACKENDS" ]]; then
  echo ""
  echo "Checking RPC backends: ${RPC_BACKENDS}"
  IFS=',' read -ra BACKENDS <<< "$RPC_BACKENDS"
  BACKENDS_OK=0
  for backend in "${BACKENDS[@]}"; do
    host="${backend%%:*}"
    port="${backend##*:}"
    if curl -s --connect-timeout 2 "http://${backend}/" >/dev/null 2>&1 || \
       nc -z -w 2 "${host}" "${port}" 2>/dev/null; then
      echo -e "  ${GRN}✓${RST} ${backend} reachable"
      ((BACKENDS_OK++)) || true
    else
      echo -e "  ${YLW}⚠${RST} ${backend} not responding (run setup-rpc-server.sh first)"
    fi
  done

  if [[ $BACKENDS_OK -eq 0 ]]; then
    echo -e "  ${RED}No backends reachable — run setup-rpc-server.sh first${RST}"
    echo -e "  ${YLW}Continuing in single-Pi mode (ignoring --rpc-backends)${RST}"
    RPC_BACKENDS=""
  else
    echo -e "  ${GRN}✓ ${BACKENDS_OK}/${#BACKENDS[@]} backends online${RST}"
  fi
fi

# ── Stop existing llama-server on Pi #1 ──────────────────────────────────────
echo ""
echo "Stopping existing llama-server on Pi #1..."
ssh ${SSH_ID} ${SSH_OPTS} "${SSH_USER}@${JUMP_HOST}" \
  "pkill -f 'llama-server' 2>/dev/null; sleep 0.5; echo stopped" 2>/dev/null || true
echo -e "  ${GRN}✓${RST} Stopped"

# ── Start llama-server with optional --rpc ───────────────────────────────────
echo ""
echo "Starting llama-server on Pi #1..."

RPC_FLAG=""
[[ -n "$RPC_BACKENDS" ]] && RPC_FLAG="--rpc ${RPC_BACKENDS}"

LOG_FILE="/tmp/llama-server-rpc.log"

ssh ${SSH_ID} ${SSH_OPTS} "${SSH_USER}@${JUMP_HOST}" "bash -s" <<REMOTE 2>/dev/null
LD_LIBRARY_PATH=${BINARY_DIR} \
setsid ${BINARY_DIR}/llama-server \
  ${RPC_FLAG} \
  -m ${MODEL_DIR}/${MODEL_FILE} \
  --host 0.0.0.0 \
  --port ${LLAMA_PORT} \
  --ctx-size ${CTX_SIZE} \
  --threads ${THREADS} \
  --n-predict -1 \
  > ${LOG_FILE} 2>&1 < /dev/null &
echo "PID: \$!"
REMOTE

echo -e "  ${YLW}Waiting for llama-server to initialise (model load takes 30-90s for large models)...${RST}"
sleep 5

# Poll for ready
for i in $(seq 1 18); do
  if curl -s --connect-timeout 2 "http://${JUMP_HOST}:${LLAMA_PORT}/health" 2>/dev/null | grep -q '"status"'; then
    echo -e "  ${GRN}✓ llama-server ready on Pi #1:${LLAMA_PORT}${RST}"
    break
  fi
  printf '.'
  sleep 5
done
echo ""

# Tail log for any errors
echo "  Recent log (Pi #1:${LOG_FILE}):"
ssh ${SSH_ID} ${SSH_OPTS} "${SSH_USER}@${JUMP_HOST}" \
  "tail -5 ${LOG_FILE}" 2>/dev/null | sed 's/^/    /'

echo ""
echo -e "${BLU}══════════════════════════════════════════════════════${RST}"
echo -e "  ${GRN}✓ RPC primary started${RST}"
echo ""
echo "  Test inference:"
echo "    curl -s http://${JUMP_HOST}:${LLAMA_PORT}/completion \\"
echo "      -d '{\"prompt\":\"Hello from RPC mesh:\",\"n_predict\":16}' | jq .content"
echo ""
if [[ -n "$RPC_BACKENDS" ]]; then
  echo "  RPC backends distributing layers across: ${RPC_BACKENDS}"
  echo "  Model ${MODEL_FILE} sharded across $(echo "${RPC_BACKENDS}" | tr ',' '\n' | wc -l | tr -d ' ') backends + Pi #1"
fi
echo -e "${BLU}══════════════════════════════════════════════════════${RST}"
echo ""

```
