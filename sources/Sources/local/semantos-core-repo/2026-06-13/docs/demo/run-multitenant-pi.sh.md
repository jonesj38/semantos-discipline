---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/docs/demo/run-multitenant-pi.sh
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.748641+00:00
---

# docs/demo/run-multitenant-pi.sh

```sh
#!/usr/bin/env bash
# run-multitenant-pi.sh — spawn N mesh-node tenant brains on a single Pi.
#
# D-SRS-multitenant-spawn: runs on each Pi to replace the single-brain
# systemd service with a local cluster of N brains on loopback, then
# starts mesh-tenant-gateway.py to bridge loopback ↔ LAN.
#
# Architecture on each Pi:
#   brain-00 … brain-N (loopback, SNS multicast group, port 47100)
#       ↕
#   mesh-tenant-gateway.py (lo → end0 bidirectional relay)
#       ↕
#   other Pis on LAN (same SNS group, port 47100)
#
# Global tile coordinate scheme (for a 3×2 grid of Pis):
#   Pi 0 → tile-x 0..3, tile-y 0..3  (top-left quad)
#   Pi 1 → tile-x 4..7, tile-y 0..3  (top-center)
#   Pi 2 → tile-x 8..11, tile-y 0..3 (top-right)
#   Pi 3 → tile-x 0..3, tile-y 4..7  (bottom-left)
#   Pi 4 → tile-x 4..7, tile-y 4..7
#   Pi 5 → tile-x 8..11, tile-y 4..7
#   (generalised: tile-x = (PI_INDEX % PI_COLS)*LOCAL_COLS + local_x
#                 tile-y = (PI_INDEX / PI_COLS)*LOCAL_ROWS + local_y)
#
# Usage (on a Pi, run as the pi user or root):
#   ./run-multitenant-pi.sh --pi-index 0 --count 4
#   ./run-multitenant-pi.sh --pi-index 2 --count 16 --iface end0
#
# Required on Pi (Armbian):
#   /usr/local/bin/mesh-node  — Zig-compiled binary (already deployed)
#   python3                   — included in Armbian base image
#   docs/demo/mesh-tenant-gateway.py — deployed alongside this script
#
# SAFETY: no real transactions; no mainnet contact; no private keys.
# The group is the SNS-derived address for mnca.tile.tick (read-only).

set -euo pipefail

# ── defaults ────────────────────────────────────────────────────────────────
COUNT=4                # brains per Pi (use 16 for full multitenant)
PI_INDEX=0             # 0-based Pi index (determines global tile offset)
PI_COLS=3              # Pis per row in the global grid (Skyminer: 3 cols)
LOCAL_COLS=2           # brain columns per Pi (sqrt(COUNT) if square)
TILE_MS=500            # MNCA step interval in ms
WAN_IFACE="end0"       # Pi LAN interface (Armbian: end0)
LOCAL_IFACE="lo"       # loopback interface (Linux: lo)
MESH_NODE_BIN="${MESH_NODE_BIN:-/usr/local/bin/mesh-node}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_DIR="/tmp/mnca-multitenant-pi${PI_INDEX}"

# SNS-derived multicast group for mnca.tile.tick (Phase 34A)
MCAST_GROUP="ff15:4ed1:aabd:873d:e970:0000:0000:0000"
MCAST_PORT=47100

# ── arg parsing ──────────────────────────────────────────────────────────────
while [[ $# -gt 0 ]]; do
  case "$1" in
    --count)      COUNT="$2";     shift 2 ;;
    --pi-index)   PI_INDEX="$2";  shift 2 ;;
    --pi-cols)    PI_COLS="$2";   shift 2 ;;
    --local-cols) LOCAL_COLS="$2"; shift 2 ;;
    --tile-ms)    TILE_MS="$2";   shift 2 ;;
    --iface)      WAN_IFACE="$2"; shift 2 ;;
    --local-iface) LOCAL_IFACE="$2"; shift 2 ;;
    --group)      MCAST_GROUP="$2"; shift 2 ;;
    *) echo "Unknown arg: $1" >&2; exit 1 ;;
  esac
done

# ── derived tile offset ───────────────────────────────────────────────────────
LOCAL_ROWS=$(( (COUNT + LOCAL_COLS - 1) / LOCAL_COLS ))
PI_ROW=$(( PI_INDEX / PI_COLS ))
PI_COL=$(( PI_INDEX % PI_COLS ))
BASE_X=$(( PI_COL * LOCAL_COLS ))
BASE_Y=$(( PI_ROW * LOCAL_ROWS ))

echo "=== run-multitenant-pi.sh ==="
echo "  Pi index:  ${PI_INDEX}  (col=${PI_COL}, row=${PI_ROW})"
echo "  Count:     ${COUNT} brains  (${LOCAL_COLS}×${LOCAL_ROWS} grid)"
echo "  Tile base: (${BASE_X}, ${BASE_Y})"
echo "  Group:     ${MCAST_GROUP}:${MCAST_PORT}"
echo "  WAN iface: ${WAN_IFACE}  local iface: ${LOCAL_IFACE}"
echo ""

# ── pre-flight ────────────────────────────────────────────────────────────────
if [[ ! -x "${MESH_NODE_BIN}" ]]; then
  echo "ERROR: mesh-node not found at ${MESH_NODE_BIN}" >&2
  echo "  Deploy with: scp zig-out/bin/mesh-node pi@192.168.0.X:/usr/local/bin/" >&2
  exit 1
fi
if ! command -v python3 &>/dev/null; then
  echo "ERROR: python3 not found" >&2; exit 1
fi

# ── config generation (inline Python — no Bun/bun needed on Pi) ───────────────
mkdir -p "${CONFIG_DIR}"

python3 - <<PYEOF
import json, os, random, string, sys

count     = ${COUNT}
base_x    = ${BASE_X}
base_y    = ${BASE_Y}
local_cols = ${LOCAL_COLS}
group     = '${MCAST_GROUP}'
port      = ${MCAST_PORT}
config_dir = '${CONFIG_DIR}'

def rand_hex(n):
    return ''.join(random.choices('0123456789abcdef', k=n*2))

nodes = [
    {
        'index': i,
        'label': f'pi${PI_INDEX}-brain-{i:02d}',
        'cellId': rand_hex(32),
        'broadcastSecret': rand_hex(32),
    }
    for i in range(count)
]

for me in nodes:
    cfg = {
        'self': {
            'label':           me['label'],
            'cellId':          me['cellId'],
            'broadcastSecret': me['broadcastSecret'],
        },
        'multicast': {
            'group':   group,
            'port':    port,
            'hops':    1,
            'loopback': True,
        },
        'peers': [
            {
                'label':           o['label'],
                'cellId':          o['cellId'],
                'broadcastSecret': o['broadcastSecret'],
            }
            for o in nodes if o['cellId'] != me['cellId']
        ],
        'meta': {
            'generatedAt': '$(date -u +%Y-%m-%dT%H:%M:%SZ)',
            'schema': 'u2-mesh-identity/v2',
            'meshSize': count,
        },
    }
    path = os.path.join(config_dir, f"{me['label']}.json")
    with open(path, 'w') as f:
        json.dump(cfg, f, indent=2)
        f.write('\n')
    print(f'  config: {path}')
PYEOF

echo ""
echo "Generated ${COUNT} node configs in ${CONFIG_DIR}"
echo ""

# ── process management ────────────────────────────────────────────────────────
PIDS=()

cleanup() {
  echo ""
  echo "Stopping all processes…"
  for pid in "${PIDS[@]:-}"; do
    kill "$pid" 2>/dev/null || true
  done
  wait 2>/dev/null || true
  echo "Stopped."
  exit 0
}
trap cleanup INT TERM

# ── launch mesh-node instances ────────────────────────────────────────────────
echo "Starting ${COUNT} mesh-node brains (loopback, --iface ${LOCAL_IFACE}):"
for (( i=0; i<COUNT; i++ )); do
  local_x=$(( i % LOCAL_COLS ))
  local_y=$(( i / LOCAL_COLS ))
  tile_x=$(( BASE_X + local_x ))
  tile_y=$(( BASE_Y + local_y ))
  label="pi${PI_INDEX}-brain-$(printf '%02d' $i)"
  cfg="${CONFIG_DIR}/${label}.json"

  "${MESH_NODE_BIN}" \
    --config   "${cfg}" \
    --tile-ms  "${TILE_MS}" \
    --tile-x   "${tile_x}" \
    --tile-y   "${tile_y}" \
    --iface    "${LOCAL_IFACE}" \
    &
  PIDS+=($!)
  echo "  [${label}] pid ${PIDS[-1]}  tile=(${tile_x},${tile_y})"
done

echo ""
echo "Starting mesh-tenant-gateway (${LOCAL_IFACE} ↔ ${WAN_IFACE}):"
python3 "${SCRIPT_DIR}/mesh-tenant-gateway.py" \
  --group       "${MCAST_GROUP}" \
  --port        "${MCAST_PORT}" \
  --local-iface "${LOCAL_IFACE}" \
  --wan-iface   "${WAN_IFACE}" \
  &
PIDS+=($!)
echo "  [gateway] pid ${PIDS[-1]}"

echo ""
echo "All processes started. Press Ctrl+C to stop."
echo ""
echo "  Global tile range: (${BASE_X}..$(( BASE_X + LOCAL_COLS - 1 )), ${BASE_Y}..$(( BASE_Y + LOCAL_ROWS - 1 )))"
echo "  SNS group:         ${MCAST_GROUP}:${MCAST_PORT}"
echo "  Verify (on Mac):   curl http://localhost:4400/tiles | python3 -m json.tool"
echo ""

# ── wait ─────────────────────────────────────────────────────────────────────
wait

```
