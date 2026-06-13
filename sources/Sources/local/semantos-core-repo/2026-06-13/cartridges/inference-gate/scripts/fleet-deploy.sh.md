---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/inference-gate/scripts/fleet-deploy.sh
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.418411+00:00
---

# cartridges/inference-gate/scripts/fleet-deploy.sh

```sh
#!/usr/bin/env bash
# fleet-deploy.sh
#
# SSHs to all reachable Pis in the Skyminer mesh and runs setup-llama-rpc-worker.sh
# (or deploys the lightweight mock-classifier worker-handler.ts) in parallel.
#
# Usage:
#   ./fleet-deploy.sh                                              # mock workers, auto-detect coordinator
#   ./fleet-deploy.sh --coordinator-ip 192.168.0.50               # explicit laptop wired IP
#   ./fleet-deploy.sh --coordinator-ip 192.168.0.50 --mode llama  # llama on all Pis
#   ./fleet-deploy.sh --coordinator-ip 192.168.0.50 --mode mock   # mock-classifier only (faster)
#   ./fleet-deploy.sh --coordinator-ip 192.168.0.50 --dry-run     # probe only, no deploy
#
# Network topology (Skyminer mesh — all directly reachable via 192.168.0.x wired):
#   Laptop:  192.168.0.50 (en8, wired) — coordinator / relay / registry
#   Pi #1:   192.168.0.4  (end0) + 192.168.20.8 (wlan0 — also WiFi subnet bridge)
#   Pi #2-7: 192.168.0.2, .3, .5, .6, .7, .8 (wired end0 only, directly reachable)
#
# Pi specialisation by index:
#   1 → inference.request.safety.*   (llama-1b recommended — confirmed working)
#   2 → inference.request.analysis.*
#   3 → inference.request.access.*
#   4 → inference.request.ppe.*
#   5 → inference.request.vision.*
#   6 → inference.request.audio.*
#   7 → inference.request.bgp.*
#   8 → inference.request.* (general fallback)
#
# Daemonize pattern (survives SSH session close):
#   setsid bun file.ts > /tmp/log 2>&1 < /dev/null &
#
# Prerequisites on each Pi (done by setup-llama-rpc-worker.sh):
#   - bun 1.3.14+ at ~/.bun/bin/bun
#   - apt HTTPS fix: http://deb.debian.org → https://deb.debian.org
#   - llama-server b9357 at /opt/semantos/bin/ (for llama mode only)
#   - Llama-3.2-1B-Instruct-Q4_K_M.gguf at /opt/semantos/models/ (for llama mode)

set -euo pipefail

# ── Defaults ──────────────────────────────────────────────────────────────────
COORDINATOR_IP="192.168.0.50"       # laptop wired IP (en8) — all Pis are on same subnet
MODE="mock"            # "mock" | "llama" | "probe"
DRY_RUN=false
SSH_USER="todriguez"
SSH_KEY="${HOME}/.ssh/id_ed25519"
SSH_OPTS="-o StrictHostKeyChecking=no -o ConnectTimeout=8 -o BatchMode=yes"
RELAY_PORT=5199
REGISTRY_PORT=5201
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORKER_HANDLER="${SCRIPT_DIR}/../worker-handler.ts"

# All Pis are directly reachable on 192.168.0.x — no jump host needed
PI_SUBNET_BASE="192.168.0"

# ── Arg parsing ───────────────────────────────────────────────────────────────
while [[ $# -gt 0 ]]; do
  case "$1" in
    --coordinator-ip) COORDINATOR_IP="$2"; shift 2 ;;
    --mode)           MODE="$2";           shift 2 ;;
    --dry-run)        DRY_RUN=true;        shift ;;
    --ssh-key)        SSH_KEY="$2";        shift 2 ;;
    --ssh-user)       SSH_USER="$2";       shift 2 ;;
    --jump-host)      echo "Warning: --jump-host ignored; all Pis directly reachable on 192.168.0.x" >&2; shift 2 ;;
    --help|-h)
      sed -n '/^#/p' "$0" | head -35 | sed 's/^# \?//'
      exit 0 ;;
    *) echo "Unknown arg: $1" >&2; exit 1 ;;
  esac
done

SSH_ID="-i ${SSH_KEY}"

RELAY_URL="http://${COORDINATOR_IP}:${RELAY_PORT}"
REGISTRY_URL="http://${COORDINATOR_IP}:${REGISTRY_PORT}"

# ── Colours ───────────────────────────────────────────────────────────────────
RED='\033[0;31m'; GRN='\033[0;32m'; YLW='\033[0;33m'; BLU='\033[0;34m'; RST='\033[0m'

# ── Pi definitions ────────────────────────────────────────────────────────────
# Format: "INDEX SSH_HOST"
# All Pis directly reachable on 192.168.0.x wired (laptop at .50)
# Pi #1 (safety/llama) is at .4; mock workers at .2, .3, .5, .6, .7, .8
declare -a PI_DEFS=(
  "1 ${PI_SUBNET_BASE}.4"
  "2 ${PI_SUBNET_BASE}.2"
  "3 ${PI_SUBNET_BASE}.3"
  "4 ${PI_SUBNET_BASE}.5"
  "5 ${PI_SUBNET_BASE}.6"
  "6 ${PI_SUBNET_BASE}.7"
  "7 ${PI_SUBNET_BASE}.8"
  "8 ${PI_SUBNET_BASE}.9"
)

# ── Worker type map ───────────────────────────────────────────────────────────
pi_type() {
  case "$1" in
    1) echo "inference.request.safety.*"   ;;
    2) echo "inference.request.analysis.*" ;;
    3) echo "inference.request.access.*"   ;;
    4) echo "inference.request.ppe.*"      ;;
    5) echo "inference.request.vision.*"   ;;
    6) echo "inference.request.audio.*"    ;;
    7) echo "inference.request.bgp.*"      ;;
    *) echo "inference.request.*"          ;;
  esac
}

# ── SSH command builder ───────────────────────────────────────────────────────
ssh_cmd() {
  local idx="$1" host="$2"
  echo "ssh ${SSH_ID} ${SSH_OPTS} ${SSH_USER}@${host}"
}

# ── Probe: test SSH reachability ──────────────────────────────────────────────
probe_pi() {
  local idx="$1" host="$2"
  local cmd
  cmd=$(ssh_cmd "$idx" "$host")
  if $cmd "echo ok" >/dev/null 2>&1; then
    echo -e "  Pi #${idx} ${GRN}✓${RST} ${host}"
    return 0
  else
    echo -e "  Pi #${idx} ${RED}✗${RST} ${host} — unreachable"
    return 1
  fi
}

# ── Deploy mock-classifier worker ─────────────────────────────────────────────
deploy_mock() {
  local idx="$1" host="$2"
  local worker_type
  worker_type=$(pi_type "$idx")

  echo -e "  ${BLU}[Pi #${idx}]${RST} deploying mock worker (${worker_type}) to ${host}..."

  # SCP latest worker-handler.ts
  scp ${SSH_ID} ${SSH_OPTS} "${WORKER_HANDLER}" "${SSH_USER}@${host}:/tmp/worker-handler.ts" 2>/dev/null

  # Write start script to Pi, execute it
  cat << SCRIPT | ssh ${SSH_ID} ${SSH_OPTS} ${SSH_USER}@${host} "cat > /tmp/start-worker.sh && chmod +x /tmp/start-worker.sh && bash /tmp/start-worker.sh"
#!/bin/bash
pkill -f worker-handler.ts 2>/dev/null; sleep 0.5
export WORKER_TYPES='${worker_type}'
export MODEL='mock'
export NODE_IP='${host}'
export RELAY_URL='http://${COORDINATOR_IP}:${RELAY_PORT}'
export REGISTRY_URL='http://${COORDINATOR_IP}:${REGISTRY_PORT}'
export WORKER_PORT=5200
export MAX_CONCURRENT=2
nohup /home/${SSH_USER}/.bun/bin/bun /tmp/worker-handler.ts > /tmp/worker-mock-${idx}.log 2>&1 &
echo \$! > /tmp/worker.pid
echo "PID: \$!"
SCRIPT
  echo -e "  ${GRN}[Pi #${idx}]${RST} worker started"
}

# ── Deploy llama worker (via setup-llama-rpc-worker.sh) ──────────────────────
deploy_llama() {
  local idx="$1" host="$2"
  local setup_script="${SCRIPT_DIR}/setup-llama-rpc-worker.sh"

  echo -e "  ${BLU}[Pi #${idx}]${RST} deploying llama worker to ${host} (this takes ~10min first time)..."

  scp ${SSH_ID} ${SSH_OPTS} "${setup_script}" "${SSH_USER}@${host}:/tmp/setup-llama-rpc-worker.sh" 2>/dev/null
  scp ${SSH_ID} ${SSH_OPTS} "${WORKER_HANDLER}" "${SSH_USER}@${host}:/tmp/worker-handler.ts" 2>/dev/null

  ssh ${SSH_ID} ${SSH_OPTS} ${SSH_USER}@${host} "bash -s" <<REMOTE 2>&1 | sed "s/^/  [Pi #${idx}] /"
chmod +x /tmp/setup-llama-rpc-worker.sh
/tmp/setup-llama-rpc-worker.sh --pi-index ${idx} --coordinator-ip ${COORDINATOR_IP}
REMOTE
}

# ── Main ──────────────────────────────────────────────────────────────────────
echo ""
echo -e "${BLU}══════════════════════════════════════════════════════${RST}"
echo -e "${BLU}  Skyminer Fleet Deploy${RST}"
echo -e "  Mode:        ${YLW}${MODE}${RST}"
echo -e "  Coordinator: ${COORDINATOR_IP}"
echo -e "  Relay:       ${RELAY_URL}"
echo -e "  Registry:    ${REGISTRY_URL}"
echo -e "${BLU}══════════════════════════════════════════════════════${RST}"
echo ""

# Step 1: probe all Pis (serial to avoid jump-host overload)
echo "Probing Pis..."
declare -a REACHABLE=()
for pi_def in "${PI_DEFS[@]}"; do
  read -r idx host <<< "$pi_def"
  if probe_pi "$idx" "$host"; then
    REACHABLE+=("$pi_def")
  fi
done

echo ""
echo -e "Reachable: ${GRN}${#REACHABLE[@]}${RST} / ${#PI_DEFS[@]}"

if [[ ${#REACHABLE[@]} -eq 0 ]]; then
  echo -e "${RED}No Pis reachable. Check SSH key and network.${RST}"
  exit 1
fi

if [[ "$DRY_RUN" == "true" ]]; then
  echo -e "\n${YLW}--dry-run: skipping deployment${RST}"
  exit 0
fi

echo ""
echo "Deploying workers (up to 4 in parallel)..."
echo ""

# Step 2: deploy in batches of 4
BATCH_SIZE=4
batch=()
for pi_def in "${REACHABLE[@]}"; do
  batch+=("$pi_def")
  if [[ ${#batch[@]} -ge $BATCH_SIZE ]]; then
    # Spawn batch in parallel
    pids=()
    for b in "${batch[@]}"; do
      read -r idx host <<< "$b"
      if [[ "$MODE" == "llama" ]]; then
        deploy_llama "$idx" "$host" &
      else
        deploy_mock "$idx" "$host" &
      fi
      pids+=($!)
    done
    # Wait for batch
    for pid in "${pids[@]}"; do wait "$pid" 2>/dev/null || true; done
    batch=()
  fi
done
# Remaining batch
if [[ ${#batch[@]} -gt 0 ]]; then
  pids=()
  for b in "${batch[@]}"; do
    read -r idx host via <<< "$b"
    if [[ "$MODE" == "llama" ]]; then
      deploy_llama "$idx" "$host" "$via" &
    else
      deploy_mock "$idx" "$host" "$via" &
    fi
    pids+=($!)
  done
  for pid in "${pids[@]}"; do wait "$pid" 2>/dev/null || true; done
fi

# Step 3: check registry
echo ""
echo -e "${BLU}══════════════════════════════════════════════════════${RST}"
echo -e "  Deployment complete — checking registry in 8s..."
echo -e "${BLU}══════════════════════════════════════════════════════${RST}"
sleep 8

echo ""
echo "Registry state:"
if curl -s "${REGISTRY_URL}/workers" 2>/dev/null | python3 -m json.tool 2>/dev/null | grep -E "workerId|nodeIp|typePaths|model|active" | sed 's/^/  /'; then
  echo ""
  ACTIVE=$(curl -s "${REGISTRY_URL}/health" 2>/dev/null | python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('activeWorkers',0))" 2>/dev/null || echo "?")
  echo -e "  Active workers: ${GRN}${ACTIVE}${RST}"
else
  echo -e "  ${RED}Registry unreachable — is worker-registry.ts running on coordinator?${RST}"
  echo -e "  Start: ${YLW}bun cartridges/inference-gate/worker-registry.ts${RST}"
fi

echo ""
echo -e "${GRN}✓ Fleet deploy done!${RST}"
echo ""
echo "  View logs on any Pi:"
echo "    ssh ${SSH_USER}@${JUMP_HOST} 'tail -20 /tmp/worker-mock-1.log'"
echo ""
echo "  E2E test:"
echo "    bun cartridges/inference-gate/scripts/llm-e2e-test.ts"
echo ""

```
