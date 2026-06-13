---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/shared/cell-store/deploy-to-pis.sh
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.435401+00:00
---

# cartridges/shared/cell-store/deploy-to-pis.sh

```sh
#!/usr/bin/env bash
# deploy-to-pis.sh — Deploy cell-store service to all reachable Skyminer Pis
#
# Scans 192.168.0.2-20 for SSH-reachable hosts running as user 'todriguez'.
# For each reachable Pi:
#   1. Copies cell-store.ts to ~/cell-store/
#   2. Installs bun if not present
#   3. Writes and enables a systemd service that runs cell-store on :5197
#      pointing back to the laptop relay at RELAY_URL
#
# Usage:
#   ./deploy-to-pis.sh                              # uses default RELAY_URL
#   RELAY_URL=http://192.168.0.50:5199 ./deploy-to-pis.sh
#
# Prerequisites:
#   - SSH key auth to todriguez@<pi-ip> (run ssh-add if needed)
#   - Pis must have systemd (Armbian Bookworm has it)
#   - Bun install requires internet access on the Pi

set -euo pipefail

RELAY_URL="${RELAY_URL:-http://192.168.20.5:5199}"  # laptop IP on LAN
CELL_STORE_PORT="${CELL_STORE_PORT:-5197}"
SSH_USER="${SSH_USER:-todriguez}"
SSH_OPTS="-o ConnectTimeout=3 -o BatchMode=yes -o StrictHostKeyChecking=no"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CELL_STORE_TS="$SCRIPT_DIR/cell-store.ts"

# Auto-derive scan subnet from RELAY_URL (first 3 octets of the host IP).
# Override with PI_SUBNET=192.168.20 if needed.
_relay_host="${RELAY_URL#*://}"          # strip scheme
_relay_host="${_relay_host%%:*}"         # strip port
_relay_host="${_relay_host%%/*}"         # strip path
PI_SUBNET="${PI_SUBNET:-${_relay_host%.*}}"   # keep first 3 octets

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  Skyminer cell-store deploy"
echo "  Relay:  $RELAY_URL"
echo "  Subnet: $PI_SUBNET.2-20"
echo "  Port:   $CELL_STORE_PORT"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

FOUND=0
DEPLOYED=0
FAILED=()

for LAST in $(seq 2 20); do
  IP="$PI_SUBNET.$LAST"

  # Quick reachability check
  if ! ssh $SSH_OPTS "$SSH_USER@$IP" "echo ok" >/dev/null 2>&1; then
    continue
  fi

  FOUND=$((FOUND + 1))
  echo ""
  echo "▸ Found Pi at $IP"

  # Copy cell-store.ts
  echo "  copying cell-store.ts…"
  ssh $SSH_OPTS "$SSH_USER@$IP" "mkdir -p ~/cell-store"
  scp -q $SSH_OPTS "$CELL_STORE_TS" "$SSH_USER@$IP:~/cell-store/cell-store.ts"

  # Install bun if missing
  echo "  checking bun…"
  if ! ssh $SSH_OPTS "$SSH_USER@$IP" "command -v bun" >/dev/null 2>&1; then
    echo "  installing bun (requires internet on Pi)…"
    ssh $SSH_OPTS "$SSH_USER@$IP" \
      "curl -fsSL https://bun.sh/install | bash" >/dev/null 2>&1 || {
      echo "  ✗ bun install failed on $IP — skipping"
      FAILED+=("$IP")
      continue
    }
  else
    BUN_VER=$(ssh $SSH_OPTS "$SSH_USER@$IP" "bun --version 2>/dev/null || echo unknown")
    echo "  bun $BUN_VER already installed"
  fi

  # Write systemd service
  echo "  writing systemd service…"
  ssh $SSH_OPTS "$SSH_USER@$IP" "sudo tee /etc/systemd/system/cell-store.service > /dev/null" <<EOF
[Unit]
Description=Skyminer cell-store — mesh cell persistence (:$CELL_STORE_PORT)
After=network.target

[Service]
Type=simple
User=$SSH_USER
WorkingDirectory=/home/$SSH_USER/cell-store
ExecStart=/home/$SSH_USER/.bun/bin/bun cell-store.ts --port $CELL_STORE_PORT --relay $RELAY_URL --db /home/$SSH_USER/cell-store/cells.sqlite
Restart=on-failure
RestartSec=5
Environment=HOME=/home/$SSH_USER

[Install]
WantedBy=multi-user.target
EOF

  # Enable and start
  echo "  enabling + starting service…"
  ssh $SSH_OPTS "$SSH_USER@$IP" "sudo systemctl daemon-reload && sudo systemctl enable cell-store --now" >/dev/null 2>&1

  # Verify it's running
  sleep 1
  STATUS=$(ssh $SSH_OPTS "$SSH_USER@$IP" "systemctl is-active cell-store 2>/dev/null || echo unknown")
  if [[ "$STATUS" == "active" ]]; then
    echo "  ✓ cell-store active on $IP:$CELL_STORE_PORT"
    DEPLOYED=$((DEPLOYED + 1))
  else
    echo "  ✗ service status: $STATUS on $IP"
    ssh $SSH_OPTS "$SSH_USER@$IP" "journalctl -u cell-store -n 10 --no-pager" 2>/dev/null || true
    FAILED+=("$IP")
  fi
done

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  Done. Scanned $PI_SUBNET.2-20"
echo "  Found:    $FOUND Pis"
echo "  Deployed: $DEPLOYED"
if [[ ${#FAILED[@]} -gt 0 ]]; then
  echo "  Failed:   ${FAILED[*]}"
fi
echo ""
echo "  Each Pi cell-store subscribes to relay SSE ($RELAY_URL/cells/stream)"
echo "  with polling fallback. Cells stored in ~/cell-store/cells.sqlite."
echo "  Query any Pi:  curl http://<pi-ip>:$CELL_STORE_PORT/cells/stats"
echo "                 curl http://<pi-ip>:$CELL_STORE_PORT/health"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

```
