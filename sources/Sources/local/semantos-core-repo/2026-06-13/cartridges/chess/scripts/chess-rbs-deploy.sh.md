---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/chess/scripts/chess-rbs-deploy.sh
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.423594+00:00
---

# cartridges/chess/scripts/chess-rbs-deploy.sh

```sh
#!/usr/bin/env bash
# chess-rbs-deploy.sh — deploy chess Phase-2 manifest to rbs and restart the brain.
#
# Usage:
#   bash cartridges/chess/scripts/chess-rbs-deploy.sh \
#     --manifest path/to/chess-anchors-manifest-*.json \
#     [--host todd@rbs] \
#     [--data-dir /var/lib/semantos]
#
# What it does:
#   1. Validates the manifest JSON locally
#   2. SCP manifest.json → /tmp/chess-manifest.json on rbs (todd-writable)
#   3. sudo install → <data-dir>/chess/manifest.json (semantos-owned, 0640)
#   4. sudo systemctl restart semantos-shell.service
#   5. Wait 3s, tail log to confirm chess is running
#
# The brain reads <data-dir>/chess/manifest.json at startup. If valid, it
# wires up the chess_wallet_port → Phase-2 real sats are live. If missing
# or invalid, the brain falls back to Phase-1 notional sats.
#
# Payouts happen browser-side via wallet.html → "Claim winnings" button.
# No server-side submitter or signing key is needed.
#
# Prerequisites:
#   - SSH key auth to rbs (no password prompt)
#   - Passwordless sudo for systemctl restart (or will prompt)
#   - todd user has sudo access to install files into /var/lib/semantos
#
# Source manifest from:
#   wallet.html → Chess stake panel → "Export anchors manifest" button

set -euo pipefail

MANIFEST_PATH=""
RBS_HOST="todd@rbs"
DATA_DIR="/var/lib/semantos"

# ── Arg parse ──────────────────────────────────────────────────────────
while [[ $# -gt 0 ]]; do
  case "$1" in
    --manifest) MANIFEST_PATH="$2"; shift 2 ;;
    --host)     RBS_HOST="$2"; shift 2 ;;
    --data-dir) DATA_DIR="$2"; shift 2 ;;
    -h|--help)
      sed -n '2,30p' "$0"
      exit 0
      ;;
    *) echo "unknown arg: $1"; exit 2 ;;
  esac
done

if [[ -z "$MANIFEST_PATH" ]]; then
  echo "error: --manifest <path> is required"
  echo "       (download from wallet.html → Chess stake panel → Export anchors manifest)"
  exit 2
fi

if [[ ! -f "$MANIFEST_PATH" ]]; then
  echo "error: manifest file not found: $MANIFEST_PATH"
  exit 2
fi

CHESS_DIR="${DATA_DIR}/chess"

# ── Validate JSON locally before touching rbs ──────────────────────────
echo "validating manifest JSON..."
python3 - "$MANIFEST_PATH" <<'EOF'
import json, sys
with open(sys.argv[1]) as f:
    m = json.load(f)
assert m.get('version') == 1, 'missing version:1'
anchors = m.get('anchors', [])
assert len(anchors) > 0, 'no anchors in manifest'
print(f'  ok: {len(anchors)} anchor(s) found')
for a in anchors:
    assert all(k in a for k in ['game_id','color','outpoint','satoshis']), f'anchor missing required fields: {a}'
    print(f'  anchor: gameId={a["game_id"]} color={a["color"]} sats={a["satoshis"]} txid={a["outpoint"]["txid_be"][:16]}…:{a["outpoint"]["vout"]}')
EOF

echo ""

# ── SCP manifest to temp location, then sudo install ─────────────────
echo "copying manifest to ${RBS_HOST}..."
scp "$MANIFEST_PATH" "${RBS_HOST}:/tmp/chess-manifest-upload.json"
ssh "$RBS_HOST" "
  set -e
  sudo mkdir -p ${CHESS_DIR}/intents
  sudo install -o semantos -g semantos -m 0640 /tmp/chess-manifest-upload.json ${CHESS_DIR}/manifest.json
  rm -f /tmp/chess-manifest-upload.json
  echo '  ✓ manifest installed: ${CHESS_DIR}/manifest.json'
  ls -la ${CHESS_DIR}/manifest.json
"

# ── Restart brain ──────────────────────────────────────────────────────
echo ""
echo "restarting semantos-shell.service on ${RBS_HOST}..."
ssh "$RBS_HOST" "sudo systemctl restart semantos-shell.service"
echo "  ✓ service restarted"

# ── Verify startup ─────────────────────────────────────────────────────
echo ""
echo "waiting 3s for brain to start..."
sleep 3

echo "checking brain log for chess wallet status..."
CHESS_LOG=$(ssh "$RBS_HOST" "sudo journalctl -u semantos-shell.service -n 40 --no-pager 2>/dev/null" | grep -i "chess" || true)
if echo "$CHESS_LOG" | grep -q "manifest parse failed"; then
  echo ""
  echo "  ✗ manifest parse FAILED — brain is in Phase-1 (no real escrow)"
  echo "    log snippet:"
  echo "$CHESS_LOG" | grep -i "chess" | head -5 | sed 's/^/    /'
  echo ""
  echo "  Check the manifest JSON — it must match the schema expected by"
  echo "  chess_wallet_port.loadManifestJson (see cartridges/chess/brain/chess_wallet_port.zig)"
  exit 1
else
  echo "  ✓ no manifest parse errors — Phase-2 wallet port likely active"
  echo "    (brain doesn't log a success message; absence of error = success)"
fi

echo ""
echo "done. Summary:"
echo "  manifest: ${CHESS_DIR}/manifest.json"
echo ""
echo "To claim payouts:"
echo "  Open wallet.html → Chess stake panel → enter gameId + bearer → click 'Claim winnings'"
echo "  Payouts happen entirely in the browser; no server-side submitter needed."

```
