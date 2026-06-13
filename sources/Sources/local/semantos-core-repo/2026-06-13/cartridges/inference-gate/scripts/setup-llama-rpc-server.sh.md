---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/inference-gate/scripts/setup-llama-rpc-server.sh
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.418688+00:00
---

# cartridges/inference-gate/scripts/setup-llama-rpc-server.sh

```sh
#!/usr/bin/env bash
# setup-rpc-server.sh
#
# Installs rpc-server on a worker Pi and starts it.
# Run this on Pi #2, #3, #4 to prepare them as RPC backends for Pi #1.
#
# Usage (from laptop — this script SSHes and SCPs automatically):
#   ./setup-rpc-server.sh --pi-index 2
#   ./setup-rpc-server.sh --pi-index 3
#   ./setup-rpc-server.sh --pi-index 2 3 4   # multiple Pis
#
# What it does:
#   1. Checks if rpc-server binary exists at /opt/semantos/bin/ on Pi #1
#   2. SCPs rpc-server from Pi #1 to the target Pi (via jump host)
#   3. Kills any existing rpc-server on the target Pi
#   4. Starts rpc-server on port 50052 (daemonized via setsid)
#
# Network topology:
#   Pi #1: 192.168.20.8 / 192.168.0.2  (source of rpc-server binary)
#   Pi #2-8: 192.168.0.3-9             (targets — reachable via jump host Pi #1)
#
# RPC architecture:
#   - Worker Pis (2-4) run rpc-server — pure compute backends
#   - Primary Pi #1 runs llama-server with --rpc 192.168.0.3:50052,...
#   - The 7B model (~4.2GB) is distributed across Pi #1 + 3 backends (~1.4GB each)
#   - Use start-llama-rpc-primary.sh on Pi #1 after all backends are up
#
# RPC binary:
#   Part of the llama.cpp b9357 build; built alongside llama-server on Pi #1.
#   Binary: /opt/semantos/bin/rpc-server
#   Deps:   /opt/semantos/bin/*.so  (libllama, libggml, etc.)

set -euo pipefail

# ── Defaults ──────────────────────────────────────────────────────────────────
SSH_USER="todriguez"
SSH_KEY="${HOME}/.ssh/id_ed25519"
SSH_OPTS="-o StrictHostKeyChecking=no -o ConnectTimeout=8 -o BatchMode=yes"
JUMP_HOST="192.168.20.8"        # Pi #1 wlan0
PI1_SUBNET_IP="192.168.0.2"     # Pi #1 end0 (LAN side)
PI_SUBNET_BASE="192.168.0"
RPC_PORT=5205                    # rpc-server port (avoid conflict with worker :5196)
BINARY_DIR="/opt/semantos/bin"

declare -a PI_INDICES=()

# ── Arg parsing ───────────────────────────────────────────────────────────────
while [[ $# -gt 0 ]]; do
  case "$1" in
    --pi-index|-p)
      shift
      while [[ $# -gt 0 && "$1" =~ ^[0-9]+$ ]]; do
        PI_INDICES+=("$1"); shift
      done
      ;;
    --ssh-key)     SSH_KEY="$2";  shift 2 ;;
    --ssh-user)    SSH_USER="$2"; shift 2 ;;
    --jump-host)   JUMP_HOST="$2"; shift 2 ;;
    --rpc-port)    RPC_PORT="$2"; shift 2 ;;
    --help|-h)
      sed -n '/^#/p' "$0" | head -50 | sed 's/^# \?//'
      exit 0 ;;
    *) echo "Unknown arg: $1" >&2; exit 1 ;;
  esac
done

if [[ ${#PI_INDICES[@]} -eq 0 ]]; then
  echo "Usage: $0 --pi-index 2 [3 4 ...]" >&2
  exit 1
fi

SSH_ID="-i ${SSH_KEY}"
RED='\033[0;31m'; GRN='\033[0;32m'; YLW='\033[0;33m'; BLU='\033[0;34m'; RST='\033[0m'

pi_host() { echo "${PI_SUBNET_BASE}.$((${1} + 1))"; }

echo ""
echo -e "${BLU}══════════════════════════════════════════════════════${RST}"
echo -e "${BLU}  Llama RPC Server Setup — Pi #${PI_INDICES[*]}${RST}"
echo -e "  RPC port: ${RPC_PORT}  |  Binary: ${BINARY_DIR}/rpc-server"
echo -e "${BLU}══════════════════════════════════════════════════════${RST}"
echo ""

# ── Step 1: Verify binary on Pi #1 ───────────────────────────────────────────
echo "Checking rpc-server on Pi #1 (${JUMP_HOST})..."
if ssh ${SSH_ID} ${SSH_OPTS} "${SSH_USER}@${JUMP_HOST}" \
    "test -f ${BINARY_DIR}/rpc-server && echo ok" 2>/dev/null | grep -q ok; then
  echo -e "  ${GRN}✓${RST} rpc-server found at Pi #1:${BINARY_DIR}/rpc-server"
else
  echo -e "  ${RED}✗${RST} rpc-server NOT found at Pi #1:${BINARY_DIR}/rpc-server"
  echo ""
  echo "  To build it, on Pi #1 run:"
  echo "    cd /opt/semantos/src/llama.cpp"
  echo "    cmake --build build --target rpc-server -j4"
  echo "    cp build/bin/rpc-server ${BINARY_DIR}/"
  echo ""
  echo "  Or download the pre-built b9357 binary from the llama.cpp release:"
  echo "    (internet may be unreliable from Pi — prefer laptop download + SCP)"
  echo ""
  echo -e "  ${YLW}Aborting — fix binary first then re-run this script.${RST}"
  exit 1
fi

# ── Step 2: Deploy to each target Pi ─────────────────────────────────────────
for idx in "${PI_INDICES[@]}"; do
  if [[ "$idx" -eq 1 ]]; then
    echo -e "  ${YLW}Skipping Pi #1 — it's the primary, not an RPC backend${RST}"
    continue
  fi

  host=$(pi_host "$idx")
  echo ""
  echo -e "${BLU}[Pi #${idx} / ${host}]${RST} Deploying rpc-server..."

  # Test reachability
  if ! ssh ${SSH_ID} ${SSH_OPTS} -J "${SSH_USER}@${JUMP_HOST}" \
      "${SSH_USER}@${host}" "echo ok" >/dev/null 2>&1; then
    echo -e "  ${RED}✗${RST} Pi #${idx} unreachable — skipping"
    continue
  fi
  echo -e "  ${GRN}✓${RST} SSH reachable"

  # Ensure /opt/semantos/bin exists on target
  ssh ${SSH_ID} ${SSH_OPTS} -J "${SSH_USER}@${JUMP_HOST}" \
    "${SSH_USER}@${host}" "sudo mkdir -p ${BINARY_DIR} && sudo chown ${SSH_USER}:${SSH_USER} ${BINARY_DIR}" 2>/dev/null

  # SCP rpc-server binary + shared libs from Pi #1 to target
  # Strategy: copy via laptop (Pi-to-Pi SCP unreliable — Pi #1 key not in other Pis)
  echo "  Copying binary from Pi #1 → laptop → Pi #${idx}..."
  LOCAL_TMP=$(mktemp -d)
  trap "rm -rf ${LOCAL_TMP}" EXIT

  # Pull from Pi #1
  scp ${SSH_ID} ${SSH_OPTS} \
    "${SSH_USER}@${JUMP_HOST}:${BINARY_DIR}/rpc-server" \
    "${LOCAL_TMP}/" 2>/dev/null && echo -e "  ${GRN}✓${RST} Binary pulled from Pi #1" \
    || { echo -e "  ${RED}✗${RST} Failed to pull binary"; continue; }

  # Pull shared libs (libllama.so, libggml*.so, etc.)
  scp ${SSH_ID} ${SSH_OPTS} \
    "${SSH_USER}@${JUMP_HOST}:${BINARY_DIR}/*.so" \
    "${LOCAL_TMP}/" 2>/dev/null || true  # .so files may not exist (static build is fine)

  # Push to target Pi
  scp ${SSH_ID} ${SSH_OPTS} -o "ProxyJump=${SSH_USER}@${JUMP_HOST}" \
    "${LOCAL_TMP}"/* \
    "${SSH_USER}@${host}:${BINARY_DIR}/" 2>/dev/null \
    && echo -e "  ${GRN}✓${RST} Binary pushed to Pi #${idx}" \
    || { echo -e "  ${RED}✗${RST} Failed to push binary"; continue; }

  # Kill old rpc-server on target, start new one
  echo "  Starting rpc-server on Pi #${idx} port ${RPC_PORT}..."
  ssh ${SSH_ID} ${SSH_OPTS} -J "${SSH_USER}@${JUMP_HOST}" \
    "${SSH_USER}@${host}" "bash -s" <<REMOTE 2>/dev/null
pkill -f 'rpc-server' 2>/dev/null; sleep 0.3
chmod +x ${BINARY_DIR}/rpc-server
LD_LIBRARY_PATH=${BINARY_DIR} \
setsid ${BINARY_DIR}/rpc-server \
  --host 0.0.0.0 \
  --port ${RPC_PORT} \
  > /tmp/llama-rpc-${idx}.log 2>&1 < /dev/null &
echo "PID: \$!"
REMOTE

  # Verify it started
  sleep 1
  if ssh ${SSH_ID} ${SSH_OPTS} -J "${SSH_USER}@${JUMP_HOST}" \
      "${SSH_USER}@${host}" "pgrep -f 'rpc-server' >/dev/null && echo running" 2>/dev/null | grep -q running; then
    echo -e "  ${GRN}✓ rpc-server running on Pi #${idx}:${RPC_PORT}${RST}"
  else
    echo -e "  ${YLW}⚠ Process not detected — check: ssh -J ${SSH_USER}@${JUMP_HOST} ${SSH_USER}@${host} 'tail /tmp/llama-rpc-${idx}.log'${RST}"
  fi
done

echo ""
echo -e "${BLU}══════════════════════════════════════════════════════${RST}"
echo "  RPC backend setup complete."
echo ""
echo "  Next step: configure Pi #1 to use these RPC backends."
echo "  Run on your laptop:"
echo ""

# Build the --rpc flag dynamically
RPC_ARGS=""
for idx in "${PI_INDICES[@]}"; do
  [[ "$idx" -eq 1 ]] && continue
  host=$(pi_host "$idx")
  RPC_ARGS+="${RPC_ARGS:+,}${host}:${RPC_PORT}"
done

echo "    ./start-llama-rpc-primary.sh --rpc-backends \"${RPC_ARGS}\""
echo ""
echo "  Or manually on Pi #1:"
echo "    pkill -f 'llama-server'"
echo "    LD_LIBRARY_PATH=${BINARY_DIR} \\"
echo "    ${BINARY_DIR}/llama-server \\"
echo "      --rpc ${RPC_ARGS} \\"
echo "      -m /opt/semantos/models/Llama-3.2-7B-Instruct-Q4_K_M.gguf \\"
echo "      --host 0.0.0.0 --port 8080 \\"
echo "      --ctx-size 2048 --threads 4 \\"
echo "      > /tmp/llama-server-rpc.log 2>&1 < /dev/null &"
echo ""
echo -e "${GRN}✓ Done${RST}"
echo ""

```
